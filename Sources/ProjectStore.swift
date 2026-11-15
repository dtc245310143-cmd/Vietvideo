import Foundation
import Combine
import UIKit

@MainActor
final class ProjectStore: ObservableObject {
    @Published var projects: [VideoProject] = []
    @Published var current: VideoProject?
    @Published var draft = ""
    @Published var status = "Chọn video trên iPhone để bắt đầu."
    @Published var busy = false
    @Published var output: URL?
    private var task: Task<Void, Never>?
    private var autosave: Task<Void, Never>?

    init() {
        do { projects = try ProjectDisk.load() }
        catch { status = "Chưa đọc được danh sách dự án: \(error.localizedDescription)" }
    }
    func open(_ project: VideoProject) {
        guard !busy else { return }
        saveDraft()
        current = project; draft = project.draft
        output = project.outputName.map { ProjectDisk.folder(project.id).appendingPathComponent($0) }
        status = "Đã mở \(project.title)."
    }
    private func update(_ project: VideoProject) throws {
        try ProjectDisk.save(project)
        current = project
        if let i = projects.firstIndex(where: { $0.id == project.id }) { projects[i] = project }
        else { projects.insert(project, at: 0) }
    }
    func scheduleSave() {
        autosave?.cancel()
        autosave = Task { try? await Task.sleep(nanoseconds: 500_000_000); if !Task.isCancelled { saveDraft() } }
    }
    func saveDraft() {
        guard var project = current, project.draft != draft else { return }
        project.draft = draft
        do { try update(project) } catch { status = "Chưa lưu được bản nháp: \(error.localizedDescription)" }
    }
    func stop() { task?.cancel() }
    func background() { saveDraft(); stop() }

    private func run(_ operation: @escaping () async throws -> Void) {
        guard !busy else { return }
        busy = true
        UIApplication.shared.isIdleTimerDisabled = true
        task = Task {
            defer { busy = false; UIApplication.shared.isIdleTimerDisabled = false }
            do { try await operation() }
            catch { status = error is CancellationError ? "Đã dừng. Dự án và phần đã hoàn thành được giữ lại." : error.localizedDescription }
        }
    }
    private nonisolated func log(_ text: String) { Task { @MainActor [weak self] in self?.status = text } }

    func importMovie(_ source: URL, temporary: Bool = false) {
        saveDraft()
        run { [self] in
            let access = source.startAccessingSecurityScopedResource()
            defer { if access { source.stopAccessingSecurityScopedResource() } }
            status = "Đang chép video vào dự án trên iPhone…"
            let duration = try await Media.duration(source)
            let name = "source." + (source.pathExtension.isEmpty ? "mp4" : source.pathExtension)
            let project = VideoProject(title: source.deletingPathExtension().lastPathComponent, duration: duration, movieName: name)
            let folder = ProjectDisk.folder(project.id)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let target = folder.appendingPathComponent(name)
            _ = try await Task.detached {
                if temporary { try FileManager.default.moveItem(at: source, to: target) }
                else { try FileManager.default.copyItem(at: source, to: target) }
            }.value
            try Task.checkCancellation()
            try update(project); draft = ""; output = nil
            status = "Đã nhập video \(Int(duration)) giây. Có thể dịch hoặc nhập phụ đề SRT có sẵn."
        }
    }

    func checkKey(key: String, model: String, language: String) {
        run { [self] in
            let client = try Gemini(key: key, model: model, language: language)
            try await client.check(log: log)
            status = "Key truy cập được model này. Chưa gọi dịch hay xác nhận hạn mức còn lại."
        }
    }

    func translate(key: String, model: String, language: String) {
        saveDraft()
        guard let initial = current else { return }
        if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            status = "Dự án đã có phụ đề. Dùng Nhận diện lại đoạn thiếu để sửa từng khoảng và giữ các chỉnh sửa của bạn."; return
        }
        run { [self] in
            let client = try Gemini(key: key, model: model, language: language)
            let folder = ProjectDisk.folder(initial.id)
            let movie = folder.appendingPathComponent(initial.movieName)
            var rows: [Subtitle] = []
            var context = ""
            var empty = 0
            let total = Int(ceil(initial.duration / 30))
            for chunk in 0..<total {
                try Task.checkCancellation()
                let start = Double(chunk) * 30, length = min(30, initial.duration - start)
                status = "Nhận diện và dịch: phần \(chunk + 1)/\(total)…"
                let audio = try await Task.detached { try await Media.audio(movie, start: start, length: length) }.value
                let tag = Media.hash(Data("ios-audio-v1|\(model)|\(language)|\(context)|".utf8) + audio)
                let cache = folder.appendingPathComponent("\(tag)-translated.json")
                let part: [Subtitle]
                if FileManager.default.fileExists(atPath: cache.path) {
                    part = try JSONDecoder().decode([Subtitle].self, from: Data(contentsOf: cache))
                } else {
                    part = try await client.translateAudio(audio, duration: length, offset: start, context: context, log: log)
                    try JSONEncoder().encode(part).write(to: cache, options: .atomic)
                }
                if part.isEmpty { empty += 1 }
                rows += part
                context = part.map { "\($0.speaker): \($0.source) → \($0.text)" }.joined(separator: "\n")
            }
            guard !rows.isEmpty else { throw AppError.message("Chưa nhận diện được lời thoại. Có thể dùng Nhận diện lại đoạn thiếu với khoảng ngắn hơn.") }
            var project = initial
            project.cues = rows; project.draft = SRT.encode(rows)
            try update(project); draft = project.draft
            status = "Đã dịch \(rows.count) câu." + (empty > 0 ? " Có \(empty) đoạn vẫn không thấy thoại sau khi thử lại; hãy kiểm tra và nhận diện lại nếu có tiếng nói." : " Có thể sửa phụ đề rồi xuất video.")
        }
    }

    func repair(start: Double, end: Double, key: String, model: String, language: String) {
        saveDraft()
        guard let initial = current else { return }
        run { [self] in
            guard start.isFinite, end.isFinite, start >= 0, start < end, end <= initial.duration else { throw AppError.message("Chọn khoảng giây hợp lệ trong video.") }
            let parsed = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : try SRT.parse(draft, duration: initial.duration)
            let existing = parsed.map { cue in
                var row = cue
                if let old = initial.cues.first(where: { abs($0.start - cue.start) < 0.002 && abs($0.end - cue.end) < 0.002 }) { row.source = old.source; row.speaker = old.speaker }
                return row
            }
            var lower = start, upper = end
            var changed = true
            while changed {
                let oldLower = lower, oldUpper = upper
                for cue in existing where cue.start < upper && cue.end > lower { lower = min(lower, cue.start); upper = max(upper, cue.end) }
                changed = lower != oldLower || upper != oldUpper
            }
            let client = try Gemini(key: key, model: model, language: language)
            let movie = ProjectDisk.folder(initial.id).appendingPathComponent(initial.movieName)
            var replacement: [Subtitle] = []
            var cursor = lower
            let context = initial.cues.filter { $0.end <= lower }.suffix(6).map { "\($0.source) → \($0.text)" }.joined(separator: "\n")
            while cursor < upper - 0.001 {
                try Task.checkCancellation()
                let length = min(10, upper - cursor), offset = cursor
                status = "Nhận diện lại \(Int(cursor))–\(Int(cursor + length)) giây…"
                let audio = try await Task.detached { try await Media.audio(movie, start: offset, length: length) }.value
                replacement += try await client.translateAudio(audio, duration: length, offset: cursor, context: context, log: log)
                cursor += length
            }
            guard !replacement.isEmpty else { throw AppError.message("Vẫn chưa nhận diện được thoại. Phụ đề cũ được giữ nguyên.") }
            let merged = (existing.filter { $0.end <= lower || $0.start >= upper } + replacement).sorted { $0.start < $1.start }
            try SRT.validate(merged, duration: initial.duration)
            let folder = ProjectDisk.folder(initial.id)
            try Data(draft.utf8).write(to: folder.appendingPathComponent("before-repair-\(UUID().uuidString).srt"), options: .atomic)
            var project = initial; project.cues = merged; project.draft = SRT.encode(merged)
            try update(project); draft = project.draft
            status = "Đã sửa khoảng \(Int(lower))–\(Int(upper)) giây; giữ phụ đề ngoài khoảng này."
        }
    }

    func export(style: CaptionStyle) {
        saveDraft()
        guard let initial = current else { return }
        run { [self] in
            let cues = try SRT.parse(draft, duration: initial.duration)
            status = "Đang chèn phụ đề và xuất MP4, giữ âm lượng tiếng gốc. Giữ ứng dụng mở…"
            let url = try await Media.export(initial, cues: cues, style: style)
            var project = initial; project.outputName = url.lastPathComponent
            try update(project); output = url
            status = "Đã xuất video. Bấm Chia sẻ video để lưu ra Tệp hoặc Ảnh."
        }
    }

    func shareSRT() -> URL? {
        saveDraft()
        guard let project = current else { return nil }
        let url = ProjectDisk.folder(project.id).appendingPathComponent("vi.srt")
        do { try Data(draft.utf8).write(to: url, options: .atomic); return url }
        catch { status = "Chưa ghi được tệp phụ đề: \(error.localizedDescription)"; return nil }
    }
}
