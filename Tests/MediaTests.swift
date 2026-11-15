import XCTest
import AVFoundation
import UIKit
@testable import VietVideoVoiceCheck

final class MediaTests: XCTestCase {
    private func source(folder: URL, rotated: Bool) async throws -> URL {
        let silent = folder.appendingPathComponent("silent.mov")
        let writer = try AVAssetWriter(url: silent, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 320, AVVideoHeightKey: 180])
        if rotated { input.transform = CGAffineTransform(rotationAngle: .pi / 2) }
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 180])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<48 {
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing else { throw writer.error ?? AppError.message("Fixture encoder stopped") }
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            var pixel: CVPixelBuffer?
            XCTAssertEqual(CVPixelBufferPoolCreatePixelBuffer(nil, try XCTUnwrap(adaptor.pixelBufferPool), &pixel), kCVReturnSuccess)
            let buffer = try XCTUnwrap(pixel)
            CVPixelBufferLockBaseAddress(buffer, [])
            let context = try XCTUnwrap(CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: 320, height: 180, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue))
            context.setFillColor(UIColor.blue.cgColor); context.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            XCTAssertTrue(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 24)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
        print("MEDIA FIXTURE: video written")
        let wave = folder.appendingPathComponent("tone.wav")
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false))
        let samples = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32000))
        samples.frameLength = 32000
        for i in 0..<32000 { samples.floatChannelData![0][i] = Float(sin(Double(i) * 2 * .pi * 440 / 16000) * 0.25) }
        do { let file = try AVAudioFile(forWriting: wave, settings: format.settings); try file.write(from: samples) }
        print("MEDIA FIXTURE: audio written")
        let videoAsset = AVURLAsset(url: silent), audioAsset = AVURLAsset(url: wave)
        let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
        let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
        let video = try XCTUnwrap(videoTracks.first)
        let audio = try XCTUnwrap(audioTracks.first)
        let composition = AVMutableComposition()
        let v = try XCTUnwrap(composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid))
        let a = try XCTUnwrap(composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid))
        try v.insertTimeRange(CMTimeRange(start: .zero, duration: CMTime(seconds: 2, preferredTimescale: 600)), of: video, at: .zero)
        v.preferredTransform = try await video.load(.preferredTransform)
        try a.insertTimeRange(CMTimeRange(start: .zero, duration: CMTime(seconds: 2, preferredTimescale: 600)), of: audio, at: .zero)
        let session = try XCTUnwrap(AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough))
        let result = folder.appendingPathComponent("source.mov")
        session.outputURL = result; session.outputFileType = .mov
        print("MEDIA FIXTURE: combining")
        await session.export()
        print("MEDIA FIXTURE: combined")
        XCTAssertEqual(session.status, .completed, "\(String(describing: session.error))")
        return result
    }

    private func amplitude(_ data: Data) -> Double {
        let values = data.dropFirst(44).withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        return sqrt(values.reduce(0.0) { $0 + pow(Double($1) / 32768, 2) } / Double(values.count))
    }

    func testLocalExportPreservesOriginalAudioAndAddsVisibleSubtitles() async throws {
        let id = UUID(), folder = ProjectDisk.folder(id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try await source(folder: folder, rotated: false)
        let originalHash = Media.hash(try Data(contentsOf: url))
        let duration = try await Media.duration(url)
        let project = VideoProject(id: id, title: "Test", duration: duration, movieName: url.lastPathComponent)
        let cue = Subtitle(start: 0.4, end: 1.6, text: "Xin chào Việt Nam")
        let target = try await Media.export(project, cues: [cue], style: CaptionStyle())
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
        XCTAssertEqual(Media.hash(try Data(contentsOf: url)), originalHash)
        let outputDuration = try await Media.duration(target)
        XCTAssertEqual(outputDuration, duration, accuracy: 0.1)
        let before = try await Media.audio(url, start: 0.1, length: 1)
        let after = try await Media.audio(target, start: 0.1, length: 1)
        XCTAssertEqual(before.count, 32044); XCTAssertEqual(after.count, 32044)
        XCTAssertEqual(amplitude(before), 0.17677, accuracy: 0.005)
        let later = try await Media.audio(url, start: 1.1, length: 0.5)
        XCTAssertEqual(amplitude(later), 0.17677, accuracy: 0.005)
        XCTAssertEqual(amplitude(after) / amplitude(before), 1, accuracy: 0.1)
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: target))
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        let (image, _) = try await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600))
        let pixels = try XCTUnwrap(image.dataProvider?.data) as Data
        let white = pixels.filter { $0 > 230 }.count
        let sourceImage = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        sourceImage.requestedTimeToleranceBefore = .zero; sourceImage.requestedTimeToleranceAfter = .zero
        let (plain, _) = try await sourceImage.image(at: CMTime(seconds: 1, preferredTimescale: 600))
        let plainPixels = try XCTUnwrap(plain.dataProvider?.data) as Data
        XCTAssertGreaterThan(white, plainPixels.filter { $0 > 230 }.count + 50)
        let failed = Task { () throws -> URL in try Task.checkCancellation(); return try await Media.export(project, cues: [cue], style: CaptionStyle()) }
        failed.cancel()
        do { _ = try await failed.value; XCTFail("Cancelled export should not finish") } catch is CancellationError {} catch { XCTFail("Unexpected cancellation error: \(error)") }
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
    }

    func testPortraitRotationSurvivesSubtitleExport() async throws {
        let id = UUID(), folder = ProjectDisk.folder(id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try await source(folder: folder, rotated: true)
        let project = VideoProject(id: id, title: "Portrait", duration: 2, movieName: url.lastPathComponent)
        let output = try await Media.export(project, cues: [Subtitle(start: 0.4, end: 1.6, text: "Video dọc")], style: CaptionStyle())
        let tracks = try await AVURLAsset(url: output).loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let size = try await track.load(.naturalSize)
        XCTAssertEqual(size.width, 180); XCTAssertEqual(size.height, 320)
    }
}
