import Foundation
import AVFoundation

struct Stretch: Codable, Equatable {
    let start, end, factor: Double
}
struct VoicePlan {
    let cue: Subtitle
    let file: URL
    let seconds: Double
    let speed: Double
}
struct DubTimeline {
    let plans: [VoicePlan]
    let stretches: [Stretch]
    let duration: Double
}

enum Dubbing {
    static func schedule(_ cues: [Subtitle], files: [URL], seconds: [Double], duration: Double) throws -> DubTimeline {
        try SRT.validate(cues, duration: duration)
        guard cues.count == files.count, cues.count == seconds.count,
              seconds.allSatisfy({ $0.isFinite && $0 > 0 }) else { throw AppError.message("Dữ liệu thời lượng giọng không hợp lệ.") }
        var plans: [VoicePlan] = [], stretches: [Stretch] = []
        var offset = 0.0
        for (i, source) in cues.enumerated() {
            var deadline = min(duration, source.end + 2)
            if i + 1 < cues.count { deadline = min(deadline, max(source.end, cues[i + 1].start - 0.12)) }
            let available = deadline - source.start
            var cue = source
            cue.start += offset
            let speed: Double
            if seconds[i] > available * 1.15 {
                let length = seconds[i] / 1.15 + 0.05
                stretches.append(Stretch(start: source.start, end: deadline, factor: length / available))
                cue.end = cue.start + length; speed = 1.15
                offset += length - available
            } else {
                cue.end = max(source.end, min(source.start + seconds[i], deadline)) + offset
                speed = max(1, seconds[i] / (cue.end - cue.start))
            }
            plans.append(VoicePlan(cue: cue, file: files[i], seconds: seconds[i], speed: min(1.15, speed)))
        }
        return DubTimeline(plans: plans, stretches: stretches, duration: duration + offset)
    }

    static func prepare(project: VideoProject, cues: [Subtitle], voice: Int, reduceHiss: Bool,
                        log: @Sendable (String) -> Void) throws -> DubTimeline {
        guard VoicePresets.names.indices.contains(voice) else { throw VoiceError.invalid("Chọn một giọng có trong danh sách.") }
        guard let assets = Bundle.main.resourceURL?.appendingPathComponent("Assets") else { throw VoiceError.invalid("Thiếu bộ giọng.") }
        let calibrationData = try Data(contentsOf: assets.appendingPathComponent("Calibration/calibration.json"))
        let calibration = try JSONDecoder().decode(Calibration.self, from: calibrationData)
        guard calibration.voices.indices.contains(voice) else { throw VoiceError.invalid("Thiếu dữ liệu giọng đã chọn; hãy cài bản cập nhật đầy đủ.") }
        let identity = calibration.voices[voice].identity ?? Media.hash(calibrationData)
        let folder = ProjectDisk.folder(project.id).appendingPathComponent("dub-voices", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var engine: VoiceEngine?
        var frontend: Phonemizer?
        var files: [URL] = [], durations: [Double] = []
        for (i, cue) in cues.enumerated() {
            try Task.checkCancellation()
            let tag = Media.hash(Data("native-voice-v1|\(identity)|\(voice)|\(reduceHiss)|\(cue.text)".utf8))
            let file = folder.appendingPathComponent(tag).appendingPathExtension("wav")
            if !FileManager.default.fileExists(atPath: file.path) {
                if engine == nil { log("Đang nạp giọng trên iPhone…"); engine = try VoiceEngine(root: assets); frontend = try Phonemizer(root: assets) }
                log("Tạo lồng tiếng: câu \(i + 1)/\(cues.count)…")
                let chunks = try frontend!.chunks(cue.text)
                var samples: [Float] = []
                for tokens in chunks {
                    try Task.checkCancellation()
                    var audio: [Float] = []
                    for attempt in 0...1 {
                        do {
                            audio = try engine!.synthesize(voice: voice, tokens: tokens, maxFrames: min(300, max(100, tokens.count * 3)), requireEnd: true, cancelled: { Task.isCancelled }, progress: { _ in })
                            break
                        } catch is CancellationError { throw CancellationError() }
                        catch { if attempt == 1 { throw error }; log("Giọng chưa hoàn chỉnh; thử tạo lại câu này…") }
                    }
                    let cleaned = clean(audio, reduceHiss: reduceHiss)
                    guard !cleaned.isEmpty else { throw VoiceError.invalid("Có câu tạo ra giọng quá nhỏ hoặc im lặng. Hãy thử lại câu này.") }
                    if !samples.isEmpty { samples += [Float](repeating: 0, count: 5760) }
                    samples += cleaned
                }
                try Task.checkCancellation()
                let temporary = folder.appendingPathComponent("\(tag).part.wav")
                do {
                    try write(samples, to: temporary)
                    try Task.checkCancellation()
                    try FileManager.default.moveItem(at: temporary, to: file)
                } catch { try? FileManager.default.removeItem(at: temporary); throw error }
            }
            let audio = try AVAudioFile(forReading: file)
            let seconds = Double(audio.length) / audio.fileFormat.sampleRate
            guard seconds.isFinite, seconds > 0 else { throw VoiceError.invalid("Tệp giọng bị hỏng; thử tạo dự án mới.") }
            files.append(file); durations.append(seconds)
        }
        let timeline = try schedule(cues, files: files, seconds: durations, duration: project.duration)
        if !timeline.stretches.isEmpty { log("Đang tự căn \(timeline.stretches.count) câu dài; giữ đủ lời và đồng bộ tiếng gốc…") }
        return timeline
    }

    static func clean(_ input: [Float], reduceHiss: Bool) -> [Float] {
        var values = input.map { $0.isFinite ? $0 : 0 }
        if reduceHiss {
            let high = Float(1 / (1 + 2 * Double.pi * 65 / 48000))
            let low = Float((2 * Double.pi * 11000 / 48000) / (1 + 2 * Double.pi * 11000 / 48000))
            var previous: Float = 0, hp: Float = 0, lp: Float = 0
            for i in values.indices { let value = values[i]; hp = high * (hp + value - previous); previous = value; lp += low * (hp - lp); values[i] = lp }
        }
        let peak = values.map { abs($0) }.max() ?? 0
        if peak > 0 { let gain = min(1.5, 0.65 / peak); for i in values.indices { values[i] *= gain } }
        var first: Int?, last: Int?
        for offset in stride(from: 0, to: values.count, by: 480) {
            let end = min(values.count, offset + 480)
            let rms = sqrt(values[offset..<end].reduce(Float(0)) { $0 + $1 * $1 } / Float(end - offset))
            if rms > 0.004 { if first == nil { first = offset }; last = end }
        }
        guard let first, let last else { return [] }
        var trimmed = Array(values[max(0, first - 2880)..<min(values.count, last + 4800)])
        let fade = min(240, trimmed.count / 2)
        if fade > 1 { for i in 0..<fade { let gain = Float(i) / Float(fade - 1); trimmed[i] *= gain; trimmed[trimmed.count - 1 - i] *= gain } }
        return trimmed
    }

    static func write(_ samples: [Float], to url: URL) throws {
        guard !samples.isEmpty, samples.allSatisfy(\.isFinite), let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { throw VoiceError.invalid("Giọng không có âm thanh đủ rõ.") }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }
}

