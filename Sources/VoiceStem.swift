import Foundation
import AVFoundation

// Build one PCM file on disk; video export never retains a decoder for every sentence.
enum VoiceStem {
    static let rate = 48000.0
    static func create(_ timeline: DubTimeline, folder: URL, progress: @Sendable (Int, Int) -> Void = { _, _ in }) throws -> URL {
        guard timeline.duration.isFinite, timeline.duration > 0,
              timeline.duration < Double(Int64.max) / rate - 1 else { throw AppError.message("Thời lượng lồng tiếng không hợp lệ.") }
        try Task.checkCancellation()
        let name = "voice-mix-" + UUID().uuidString
        let partial = folder.appendingPathComponent(name + ".part.caf")
        let target = folder.appendingPathComponent(name + ".caf")
        do {
            try autoreleasepool { try render(timeline, to: partial, progress: progress) }
            try Task.checkCancellation()
            try FileManager.default.moveItem(at: partial, to: target)
            return target
        } catch {
            try? FileManager.default.removeItem(at: partial)
            throw error
        }
    }
    private static func render(_ timeline: DubTimeline, to file: URL, progress: @Sendable (Int, Int) -> Void) throws {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096) else { throw AppError.message("Không tạo được bộ đệm âm thanh.") }
        let writer = try AVAudioFile(forWriting: file, settings: format.settings)
        let total = Int64((timeline.duration * rate).rounded())
        var position: Int64 = 0
        func silence(until end: Int64) throws {
            while position < end {
                try Task.checkCancellation()
                let count = Int(min(4096, end - position))
                buffer.frameLength = AVAudioFrameCount(count)
                buffer.floatChannelData![0].update(repeating: 0, count: count)
                try writer.write(from: buffer); position += Int64(count)
            }
        }
        for (index, plan) in timeline.plans.enumerated() {
            try Task.checkCancellation()
            guard plan.cue.start.isFinite, plan.cue.start >= 0, plan.cue.start < timeline.duration,
                  plan.seconds.isFinite, plan.seconds > 0, plan.speed.isFinite, (1...1.15).contains(plan.speed),
                  plan.seconds / plan.speed <= timeline.duration - plan.cue.start + 0.01 else { throw AppError.message("Mốc lồng tiếng nằm ngoài video.") }
            let start = Int64((plan.cue.start * rate).rounded())
            let end = min(total, start + Int64((plan.seconds / plan.speed * rate).rounded()))
            guard start >= position, end > start else { throw AppError.message("Các câu lồng tiếng bị chồng thời gian.") }
            try silence(until: start)
            progress(index + 1, timeline.plans.count)
            try autoreleasepool {
                // Local WAV metadata is loaded on the worker so each reader closes before the next clip.
                if plan.speed == 1 {
                    let audio = try AVAudioFile(forReading: plan.file)
                    let source = audio.processingFormat
                    if source.sampleRate == rate, source.channelCount == 1,
                       source.commonFormat == .pcmFormatFloat32, !source.isInterleaved {
                        // Keep natural-speed speech bit-for-bit; no time-pitch processor is needed.
                        while position < end {
                            try Task.checkCancellation()
                            try audio.read(into: buffer, frameCount: AVAudioFrameCount(min(4096, end - position)))
                            guard buffer.frameLength > 0 else { throw AppError.message("Tệp giọng kết thúc sớm; dừng để tránh mất lời.") }
                            try writer.write(from: buffer)
                            position += Int64(buffer.frameLength)
                        }
                        return
                    }
                }
                let asset = AVURLAsset(url: plan.file)
                guard let source = asset.tracks(withMediaType: .audio).first else { throw AppError.message("Không đọc được tệp giọng câu \(index + 1).") }
                let composition = AVMutableComposition()
                guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw AppError.message("Không tạo được luồng giọng.") }
                let original = CMTime(seconds: plan.seconds, preferredTimescale: 48000)
                try track.insertTimeRange(CMTimeRange(start: .zero, duration: original), of: source, at: .zero)
                track.scaleTimeRange(CMTimeRange(start: .zero, duration: original), toDuration: CMTime(value: end - start, timescale: 48000))
                let reader = try AVAssetReader(asset: composition)
                let output = AVAssetReaderAudioMixOutput(audioTracks: [track], audioSettings: [
                    AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1,
                    AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
                    AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: true])
                output.alwaysCopiesSampleData = false
                output.audioTimePitchAlgorithm = .timeDomain
                guard reader.canAdd(output) else { throw AppError.message("Không đọc được âm thanh lồng tiếng.") }
                reader.add(output)
                guard reader.startReading() else { throw reader.error ?? AppError.message("Không căn được tốc độ giọng.") }
                defer { reader.cancelReading() }
                var copied: Int64 = 0
                while true {
                    let more = try autoreleasepool { () throws -> Bool in
                        try Task.checkCancellation()
                        guard let sample = output.copyNextSampleBuffer() else { return false }
                        guard let block = CMSampleBufferGetDataBuffer(sample) else { throw AppError.message("Thiếu dữ liệu giọng.") }
                        let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                        guard pts.isFinite else { throw AppError.message("Tệp giọng có thời gian không hợp lệ.") }
                        let local = Int64((pts * rate).rounded())
                        let destination = max(start, start + local)
                        if destination >= end { return true }
                        try silence(until: min(destination, end))
                        let available = CMBlockBufferGetDataLength(block) / MemoryLayout<Float>.size
                        var offset = Int(max(0, position - (start + local)))
                        while offset < available && position < end {
                            try Task.checkCancellation()
                            let count = min(4096, available - offset, Int(end - position))
                            buffer.frameLength = AVAudioFrameCount(count)
                            let status = CMBlockBufferCopyDataBytes(block, atOffset: offset * 4, dataLength: count * 4, destination: buffer.floatChannelData![0])
                            guard status == noErr else { throw AppError.message("Không đọc được mẫu giọng.") }
                            try writer.write(from: buffer)
                            position += Int64(count); copied += Int64(count); offset += count
                        }
                        return true
                    }
                    if !more { break }
                }
                guard reader.status == .completed else { throw reader.error ?? AppError.message("Ghép câu lồng tiếng bị gián đoạn.") }
                guard copied > 0 else { throw AppError.message("Câu \(index + 1) không có âm thanh; dừng để tránh bỏ mất lời.") }
            }
            try silence(until: end)
        }
        try silence(until: total)
    }
}

