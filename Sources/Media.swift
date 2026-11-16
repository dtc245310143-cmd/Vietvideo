import Foundation
import AVFoundation
import CoreImage
import CoreText
import CryptoKit
import ImageIO

struct CaptionStyle {
    var size = 30.0
    var top = false
    var yellow = false
    var subtitleBackground: SubtitleBackground?
    var burnSubtitles = true
    var mask: MaskRegion?
    var solidMask = false
    var blurStrength = 20.0
    var logo: URL?
    var logoCorner = "topRight"
    var logoWidth = 15.0
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

    static func export(_ project: VideoProject, cues: [Subtitle], style: CaptionStyle, timeline: DubTimeline? = nil, originalVolume: Int = 100, log: @Sendable @escaping (String) -> Void = { _ in }) async throws -> URL {
        try Task.checkCancellation()
        guard !cues.isEmpty else { throw AppError.message("Chưa có phụ đề để chèn vào video.") }
        try SRT.validate(cues, duration: project.duration)
        let folder = ProjectDisk.folder(project.id)
        let source = folder.appendingPathComponent(project.movieName)
        let asset = AVURLAsset(url: source)
        guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else { throw AppError.message("Không đọc được hình video.") }
        let duration = try await asset.load(.duration)
        let composition = AVMutableComposition()
        var originalTracks: [AVMutableCompositionTrack] = []
        guard let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw AppError.message("Không tạo được luồng xuất video.") }
        try video.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceVideo, at: .zero)
        for track in try await asset.loadTracks(withMediaType: .audio).prefix(1) {
            let range = CMTimeRangeGetIntersection(try await track.load(.timeRange), otherRange: CMTimeRange(start: .zero, duration: duration))
            if range.duration.seconds > 0 {
                guard let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw AppError.message("Không tạo được luồng tiếng gốc.") }
                try audio.insertTimeRange(range, of: track, at: range.start)
                originalTracks.append(audio)
            }
        }
        if let timeline {
            guard [0,15,25,35,50,75,100].contains(originalVolume) else { throw AppError.message("Mức tiếng gốc không hợp lệ.") }
            for change in timeline.stretches.reversed() {
                composition.scaleTimeRange(CMTimeRange(start: CMTime(seconds: change.start, preferredTimescale: 48000), duration: CMTime(seconds: change.end - change.start, preferredTimescale: 48000)), toDuration: CMTime(seconds: (change.end - change.start) * change.factor, preferredTimescale: 48000))
            }
        }
        var stem: URL?
        defer { if let stem { try? FileManager.default.removeItem(at: stem) } }
        var voiceTrack: AVMutableCompositionTrack?
        if let timeline {
            let work = Task.detached {
                try VoiceStem.create(timeline, folder: folder) { index, count in
                    log("Chuẩn bị âm thanh: câu \(index)/\(count)…")
                }
            }
            stem = try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
            try Task.checkCancellation()
            let sound = AVURLAsset(url: stem!)
            guard let source = try await sound.loadTracks(withMediaType: .audio).first,
                  let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw AppError.message("Không tạo được luồng lồng tiếng.") }
            let length = CMTimeMinimum(composition.duration, try await sound.load(.duration))
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: length), of: source, at: .zero)
            voiceTrack = track
        }
        log(timeline == nil ? "Đang xuất hình ảnh và phụ đề Việt…" : "Đang xuất hình ảnh và ghép tiếng gốc với giọng Việt…")
        let transform = try await sourceVideo.load(.preferredTransform)
        let naturalSize = try await sourceVideo.load(.naturalSize)
        let bounds = CGRect(origin: .zero, size: naturalSize).applying(transform)
        let size = CGSize(width: abs(bounds.width), height: abs(bounds.height))
        guard size.width > 0, size.height > 0 else { throw AppError.message("Kích thước video không hợp lệ.") }
        video.preferredTransform = transform
        let outputCues = timeline?.plans.map(\.cue) ?? cues
        let captions = try CaptionRenderer(cues: style.burnSubtitles ? outputCues : [], style: style)
        let renderContext = CIContext(options: [.cacheIntermediates: false])
        defer { renderContext.clearCaches() }
        let base = AVVideoComposition(asset: composition, applyingCIFiltersWithHandler: { request in
            autoreleasepool {
                do {
                    let image = try captions.apply(to: request.sourceImage, at: request.compositionTime.seconds)
                    request.finish(with: image, context: renderContext)
                } catch { request.finish(with: error) }
            }
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
        if let voiceTrack {
            let mix = AVMutableAudioMix()
            let original = Double(originalVolume) / 100
            let headroom = min(1, 0.90 / (original + 0.65))
            var parameters: [AVMutableAudioMixInputParameters] = []
            for track in originalTracks {
                let value = AVMutableAudioMixInputParameters(track: track)
                value.setVolume(Float(original * headroom), at: .zero)
                value.audioTimePitchAlgorithm = .spectral
                parameters.append(value)
            }
            let voice = AVMutableAudioMixInputParameters(track: voiceTrack)
            voice.setVolume(Float(headroom), at: .zero); voice.audioTimePitchAlgorithm = .timeDomain
            parameters.append(voice); mix.inputParameters = parameters
            export.audioMix = mix
            export.audioTimePitchAlgorithm = .spectral
        }
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
    private let logo: CIImage?
    init(cues: [Subtitle], style: CaptionStyle) throws {
        guard style.subtitleBackground?.valid != false else { throw AppError.message("Màu nền phụ đề không hợp lệ.") }
        self.cues = cues; self.style = style
        cache.totalCostLimit = 16 * 1024 * 1024
        if let url = style.logo {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1024, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { throw AppError.message("Không đọc được logo kênh.") }
            logo = CIImage(cgImage: image)
        } else { logo = nil }
    }
    func apply(to source: CIImage, at seconds: Double) throws -> CIImage {
        let extent = source.extent
        var background = source
        if let mask = style.mask {
            guard mask.valid else { throw AppError.message("Vùng làm mờ nằm ngoài video.") }
            let rect = CGRect(x: extent.minX + extent.width * mask.x, y: extent.minY + extent.height * (1 - mask.y - mask.height), width: extent.width * mask.width, height: extent.height * mask.height)
            let covered = style.solidMask ? CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0.82)).cropped(to: rect) : source.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: style.blurStrength]).cropped(to: rect)
            background = covered.composited(over: background)
        }
        if let logo {
            let scale = min(extent.width * style.logoWidth / 100 / logo.extent.width, extent.height * 0.3 / logo.extent.height)
            let resized = logo.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let padding = max(8, extent.width * 0.025)
            let x = style.logoCorner.hasSuffix("Left") ? extent.minX + padding : extent.maxX - padding - resized.extent.width
            let y = style.logoCorner.hasPrefix("top") ? extent.maxY - padding - resized.extent.height : extent.minY + padding
            background = resized.transformed(by: CGAffineTransform(translationX: x, y: y)).composited(over: background)
        }
        var low = 0, high = cues.count
        while low < high {
            let middle = (low + high) / 2
            if cues[middle].start <= seconds { low = middle + 1 } else { high = middle }
        }
        guard low > 0, seconds < cues[low - 1].end else { return background.cropped(to: extent) }
        let text = cues[low - 1].text
        let key = "\(extent.width)|\(extent.height)|\(text)" as NSString
        let image: CIImage
        if let cached = cache.object(forKey: key) { image = cached }
        else {
            image = try bitmap(text, width: extent.width, height: extent.height)
            cache.setObject(image, forKey: key, cost: Int(image.extent.width * image.extent.height * 4))
        }
        let y = style.top ? extent.maxY - extent.height * 0.07 - image.extent.height : extent.minY + extent.height * 0.07
        let x = extent.minX + (extent.width - image.extent.width) / 2
        return image.transformed(by: CGAffineTransform(translationX: x, y: y)).composited(over: background).cropped(to: extent)
    }
    private func bitmap(_ text: String, width: CGFloat, height: CGFloat) throws -> CIImage {
        let fontSize = max(14, width / 1080 * style.size)
        let font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, fontSize, nil)
        var alignment = CTTextAlignment.center
        let paragraph = withUnsafePointer(to: &alignment) { pointer in
            let setting = CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: pointer)
            return CTParagraphStyleCreate([setting], 1)
        }
        let color: CGColor
        if let box = style.subtitleBackground { color = CGColor(gray: box.usesDarkText ? 0 : 1, alpha: 1) }
        else { color = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: style.yellow ? [1, 1, 0, 1] : [1, 1, 1, 1])! }
        let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph]
        let string = NSAttributedString(string: text, attributes: attributes)
        let setter = CTFramesetterCreateWithAttributedString(string as CFAttributedString)
        let maximumWidth = floor(width * 0.9)
        let padX: CGFloat = style.subtitleBackground == nil ? 6 : max(6, ceil(fontSize * 0.5))
        let padY: CGFloat = style.subtitleBackground == nil ? 6 : max(4, ceil(fontSize * 0.25))
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(location: 0, length: string.length), nil, CGSize(width: max(1, maximumWidth - 2 * padX), height: 10000), nil)
        let w = Int(style.subtitleBackground == nil ? maximumWidth : min(maximumWidth, ceil(suggested.width) + 2 * padX))
        let h = Int(min(height * 0.4, ceil(suggested.height) + 2 * padY))
        guard w > 2 * Int(padX), h > 2 * Int(padY), let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw AppError.message("Không đủ bộ nhớ để vẽ phụ đề.") }
        if let box = style.subtitleBackground {
            context.setFillColor(CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [CGFloat(box.red), CGFloat(box.green), CGFloat(box.blue), 1])!)
            let corner = min(ceil(fontSize * 0.3), CGFloat(h) / 2)
            context.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)), cornerWidth: corner, cornerHeight: corner, transform: nil))
            context.fillPath()
        } else {
            context.setShadow(offset: CGSize(width: 1, height: -1), blur: 2, color: CGColor(gray: 0, alpha: 1))
        }
        let path = CGPath(rect: CGRect(x: padX, y: padY, width: CGFloat(w) - 2 * padX, height: CGFloat(h) - 2 * padY), transform: nil)
        CTFrameDraw(CTFramesetterCreateFrame(setter, CFRange(location: 0, length: string.length), path, nil), context)
        guard let cg = context.makeImage() else { throw AppError.message("Chưa vẽ được chữ phụ đề.") }
        return CIImage(cgImage: cg)
    }
}

