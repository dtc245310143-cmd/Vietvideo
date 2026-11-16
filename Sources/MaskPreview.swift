import Foundation
import CoreGraphics
import AVFoundation

enum MaskPreview {
    static func frame(url: URL, seconds: Double, duration: Double) async throws -> (image: CGImage, time: Double) {
        try Task.checkCancellation()
        guard seconds.isFinite, duration.isFinite, duration > 0 else { throw AppError.message("Mốc xem trước video không hợp lệ.") }
        let time = max(0, min(seconds, duration - min(0.05, duration / 2)))
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1000, height: 1000)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
        do {
            let result = try await withTaskCancellationHandler(operation: {
                try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600))
            }, onCancel: { generator.cancelAllCGImageGeneration() })
            try Task.checkCancellation()
            return (result.image, result.actualTime.seconds.isFinite ? result.actualTime.seconds : time)
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw error
        }
    }
}
