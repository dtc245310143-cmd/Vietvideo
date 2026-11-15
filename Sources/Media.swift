import Foundation
import AVFoundation
import CoreImage
import CoreText
import CryptoKit

struct CaptionStyle {
    var size = 30.0
    var top = false
    var yellow = false
}

enum Media {
    static func duration(_ url: URL) async throws -> Double {
        let asset = AVURLAsset(url: url)
        let value = try await asset.load(.duration).seconds
        guard value.isFinite, value > 0, !(try await asset.loadTracks(withMediaType: .video)).isEmpty else {
            throw AppError.message("Tệp này không có video hợp lệ hoặc iPhone chưa hỗ trợ định dạng.")
        }
        return value
    }

    static func audio(_ url: URL, start: Double, length: Double) async throws -> Data {
        try Task.checkCancellation()
        let asset = AVURLAsset(url: url)
        let tracks = Array(try await asset.loadTracks(withMediaType: .audio).prefix(1))
        guard !tracks.isEmpty else { throw AppError.message("Video không có âm thanh để nhận diện.") }
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 16000), duration: CMTime(seconds: length, preferredTimescale: 16000))
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw AppError.message("Không đọc được âm thanh của định dạng video này.") }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? AppError.message("Không tách được âm thanh.") }
        let frames = Int((length * 16000).rounded())
        var pcm = Data(count: frames * 2)
        do {
            while let sample = output.copyNextSampleBuffer() {
                try Task.checkCancellation()
                guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
                let count = CMBlockBufferGetDataLength(block)
                if count == 0 { continue }
                var raw = Data(count: count)
                let status = raw.withUnsafeMutableBytes { bytes in CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count, destination: bytes.baseAddress!) }
                guard status == noErr else { throw AppError.message("Không đọc được mẫu âm thanh.") }
                let position = Int(((CMSampleBufferGetPresentationTimeStamp(sample).seconds - start) * 16000).rounded())
                let skip = max(0, -position) * 2
                let destination = max(0, position) * 2
                let copied = min(count - skip, pcm.count - destination)
                if copied > 0 { pcm.replaceSubrange(destination..<destination + copied, with: raw[skip..<skip + copied]) }
            }
            if reader.status == .failed { throw reader.error ?? AppError.message("Đọc âm thanh bị gián đoạn.") }
        } catch { reader.cancelReading(); throw error }
        return wav(pcm)
    }

    static func wav(_ pcm: Data) -> Data {
        var out = Data("RIFF".utf8)
        func add<T: FixedWidthInteger>(_ value: T) { var v = value.littleEndian; withUnsafeBytes(of: &v) { out.append(contentsOf: $0) } }
        add(UInt32(pcm.count + 36)); out.append(Data("WAVEfmt ".utf8))
        add(UInt32(16)); add(UInt16(1)); add(UInt16(1)); add(UInt32(16000)); add(UInt32(32000)); add(UInt16(2)); add(UInt16(16))
        out.append(Data("data".utf8)); add(UInt32(pcm.count)); out.append(pcm)
        return out
    }

    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    static func export(_ project: VideoProject, cues: [Subtitle], style: CaptionStyle) async throws -> URL {
        try Task.checkCancellation()
        guard !cues.isEmpty else { throw AppError.message("Chưa có phụ đề để chèn vào video.") }
        try SRT.validate(cues, duration: project.duration)
        let folder = ProjectDisk.folder(project.id)
        let source = folder.appendingPathComponent(project.movieName)
        let asset = AVURLAsset(url: source)
        guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else { throw AppError.message("Không đọc được hình video.") }
        let duration = try await asset.load(.duration)
        let composition = AVMutableComposition()
        guard let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw AppError.message("Không tạo được luồng xuất video.") }
        try video.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceVideo, at: .zero)
        for track in try await asset.loadTracks(withMediaType: .audio).prefix(1) {
            let range = CMTimeRangeGetIntersection(try await track.load(.timeRange), otherRange: CMTimeRange(start: .zero, duration: duration))
            if range.duration.seconds > 0 {
                guard let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw AppError.message("Không tạo được luồng tiếng gốc.") }
                try audio.insertTimeRange(range, of: track, at: range.start)
            }
        }
        let transform = try await sourceVideo.load(.preferredTransform)
        let naturalSize = try await sourceVideo.load(.naturalSize)
        let bounds = CGRect(origin: .zero, size: naturalSize).applying(transform)
        let size = CGSize(width: abs(bounds.width), height: abs(bounds.height))
        guard size.width > 0, size.height > 0 else { throw AppError.message("Kích thước video không hợp lệ.") }
        video.preferredTransform = transform
        let captions = CaptionRenderer(cues: cues, style: style)
        let base = AVVideoComposition(asset: composition, applyingCIFiltersWithHandler: { request in
            do {
                let image = try captions.apply(to: request.sourceImage, at: request.compositionTime.seconds)
                request.finish(with: image, context: nil)
            } catch { request.finish(with: error) }
        })
        let videoComposition = base.mutableCopy() as! AVMutableVideoComposition
        videoComposition.renderSize = size
        let rate = try await sourceVideo.load(.nominalFrameRate)
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(1, min(60, rate.rounded()))))
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else { throw AppError.message("iPhone không hỗ trợ xuất video này.") }
        guard export.supportedFileTypes.contains(.mp4) else { throw AppError.message("Định dạng nguồn chưa hỗ trợ xuất MP4 trên iPhone.") }
        let partial = folder.appendingPathComponent("export-\(UUID().uuidString).part.mp4")
        let target = folder.appendingPathComponent("vietsub-\(UUID().uuidString).mp4")
        export.outputURL = partial
        export.outputFileType = .mp4
        export.videoComposition = videoComposition
        export.shouldOptimizeForNetworkUse = true
        do {
            try await withTaskCancellationHandler(operation: {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    export.exportAsynchronously {
                        switch export.status {
                        case .completed: continuation.resume()
                        case .cancelled: continuation.resume(throwing: CancellationError())
                        default: continuation.resume(throwing: export.error ?? AppError.message("Xuất video chưa hoàn thành."))
                        }
                    }
                }
            }, onCancel: { export.cancelExport() })
            try Task.checkCancellation()
            try FileManager.default.moveItem(at: partial, to: target)
            return target
        } catch { try? FileManager.default.removeItem(at: partial); throw error }
    }

}

private final class CaptionRenderer {
    private let cues: [Subtitle]
    private let style: CaptionStyle
    private let cache = NSCache<NSString, CIImage>()
    init(cues: [Subtitle], style: CaptionStyle) {
        self.cues = cues; self.style = style
        cache.totalCostLimit = 16 * 1024 * 1024
    }
    func apply(to source: CIImage, at seconds: Double) throws -> CIImage {
        var low = 0, high = cues.count
        while low < high {
            let middle = (low + high) / 2
            if cues[middle].start <= seconds { low = middle + 1 } else { high = middle }
        }
        guard low > 0, seconds < cues[low - 1].end else { return source }
        let text = cues[low - 1].text
        let extent = source.extent
        let key = "\(extent.width)|\(extent.height)|\(text)" as NSString
        let image: CIImage
        if let cached = cache.object(forKey: key) { image = cached }
        else {
            image = try bitmap(text, width: extent.width, height: extent.height)
            cache.setObject(image, forKey: key, cost: Int(image.extent.width * image.extent.height * 4))
        }
        let y = style.top ? extent.maxY - extent.height * 0.07 - image.extent.height : extent.minY + extent.height * 0.07
        let x = extent.minX + (extent.width - image.extent.width) / 2
        return image.transformed(by: CGAffineTransform(translationX: x, y: y)).composited(over: source).cropped(to: extent)
    }
    private func bitmap(_ text: String, width: CGFloat, height: CGFloat) throws -> CIImage {
        let font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, max(14, width / 1080 * style.size), nil)
        var alignment = CTTextAlignment.center
        let paragraph = withUnsafePointer(to: &alignment) { pointer in
            let setting = CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: pointer)
            return CTParagraphStyleCreate([setting], 1)
        }
        let color = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: style.yellow ? [1, 1, 0, 1] : [1, 1, 1, 1])!
        let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph]
        let string = NSAttributedString(string: text, attributes: attributes)
        let setter = CTFramesetterCreateWithAttributedString(string as CFAttributedString)
        let w = Int((width * 0.9).rounded(.down))
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(location: 0, length: string.length), nil, CGSize(width: CGFloat(max(1, w - 12)), height: 10000), nil)
        let h = Int(min(height * 0.4, ceil(suggested.height) + 12))
        guard w > 0, h > 0, let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw AppError.message("Không đủ bộ nhớ để vẽ phụ đề.") }
        context.setShadow(offset: CGSize(width: 1, height: -1), blur: 2, color: CGColor(gray: 0, alpha: 1))
        let path = CGPath(rect: CGRect(x: 6, y: 6, width: CGFloat(w - 12), height: CGFloat(h - 12)), transform: nil)
        CTFrameDraw(CTFramesetterCreateFrame(setter, CFRange(location: 0, length: string.length), path, nil), context)
        guard let cg = context.makeImage() else { throw AppError.message("Chưa vẽ được chữ phụ đề.") }
        return CIImage(cgImage: cg)
    }
}
