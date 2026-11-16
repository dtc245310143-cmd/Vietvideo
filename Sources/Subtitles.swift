import Foundation

struct Subtitle: Codable, Identifiable, Equatable {
    var id = UUID()
    var start: Double
    var end: Double
    var source = ""
    var text: String
    var speaker = ""
}

enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

enum SRT {
    static func validate(_ cues: [Subtitle], duration: Double) throws {
        var previous = 0.0
        for (i, cue) in cues.enumerated() {
            guard cue.start.isFinite, cue.end.isFinite, cue.start >= 0,
                  cue.end > cue.start, cue.end <= duration + 0.05,
                  cue.start >= previous - 0.001, !cue.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AppError.message("Câu \(i + 1) sai thời gian, chồng lên câu trước hoặc thiếu nội dung. Hãy sửa phụ đề trước khi xuất.")
            }
            previous = cue.end
        }
    }

    static func time(_ value: String) throws -> Double {
        let parts = value.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".").split(separator: ":")
        guard parts.count == 3, let h = Int(parts[0]), let m = Int(parts[1]), let s = Double(parts[2]),
              h >= 0, (0..<60).contains(m), s.isFinite, s >= 0, s < 60 else {
            throw AppError.message("Mốc thời gian cần có dạng 00:00:01,500.")
        }
        return Double(h * 3600 + m * 60) + s
    }

    static func parse(_ text: String, duration: Double) throws -> [Subtitle] {
        let normalized = text.replacingOccurrences(of: "\u{feff}", with: "").replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let blocks = normalized.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var rows: [Subtitle] = []
        for block in blocks {
            var lines = block.components(separatedBy: "\n")
            if let first = lines.first, Int(first.trimmingCharacters(in: .whitespaces)) != nil { lines.removeFirst() }
            guard let first = lines.first else { continue }
            let times = first.components(separatedBy: "-->")
            guard times.count == 2 else { throw AppError.message("Có câu thiếu dòng thời gian trong phụ đề.") }
            let start = try time(times[0]), end = try time(times[1])
            let content = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            rows.append(Subtitle(start: start, end: end, text: content))
        }
        guard !rows.isEmpty else { throw AppError.message("Phụ đề đang trống.") }
        try validate(rows, duration: duration)
        return rows
    }

    static func stamp(_ seconds: Double) -> String {
        let ms = Int((seconds * 1000).rounded())
        return String(format: "%02d:%02d:%02d,%03d", ms / 3600000, ms / 60000 % 60, ms / 1000 % 60, ms % 1000)
    }

    static func encode(_ cues: [Subtitle]) -> String {
        cues.enumerated().map { i, cue in "\(i + 1)\n\(stamp(cue.start)) --> \(stamp(cue.end))\n\(cue.text)\n" }.joined(separator: "\n")
    }
}

struct VideoProject: Codable, Identifiable {
    var id = UUID()
    var title: String
    var created = Date()
    var duration: Double
    var movieName: String
    var cues: [Subtitle] = []
    var draft = ""
    var outputName: String?
    var settings: ExportSettings?
    var sourceURL: String?
}

struct MaskRegion: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var valid: Bool { [x, y, width, height].allSatisfy(\.isFinite) && x >= 0 && y >= 0 && width > 0 && height > 0 && x + width <= 1.00001 && y + height <= 1.00001 }
}
struct ExportSettings: Codable, Equatable {
    var dub = false
    var burnSubtitles = true
    var voice = 0
    var originalVolume = 25
    var reduceHiss = true
    var size = 30.0
    var top = false
    var yellow = false
    var mask: MaskRegion?
    var solidMask = false
    var blurStrength = 20.0
    var logoName: String?
    var logoCorner = "topRight"
    var logoWidth = 15.0

    func validate() throws {
        guard [0,15,25,35,50,75,100].contains(originalVolume), VoicePresets.names.indices.contains(voice),
              [26.0,30,36].contains(size), mask?.valid != false, blurStrength.isFinite, (5...40).contains(blurStrength),
              logoWidth.isFinite, (5...30).contains(logoWidth), ["topLeft","topRight","bottomLeft","bottomRight"].contains(logoCorner),
              logoName == nil || logoName == "channel-logo.png" else { throw AppError.message("Tùy chỉnh xuất video không hợp lệ.") }
    }
}

enum ProjectDisk {
    static var root: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("VietVideo", isDirectory: true)
    }
    static func folder(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    static func remove(_ id: UUID) throws {
        let directory = folder(id)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }
    static func save(_ project: VideoProject) throws {
        let folder = folder(project.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(project)
        try data.write(to: folder.appendingPathComponent("project.json"), options: .atomic)
    }
    static func load() throws -> [VideoProject] {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).compactMap { folder in
            let path = folder.appendingPathComponent("project.json")
            guard FileManager.default.fileExists(atPath: path.path) else { return nil }
            return try JSONDecoder().decode(VideoProject.self, from: Data(contentsOf: path))
        }.sorted { $0.created > $1.created }
    }
}

