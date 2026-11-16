import XCTest
import AVFoundation
@testable import VietVideoVoiceCheck

final class PhonemizerTests: XCTestCase {
    struct Fixture: Decodable { let text, phones: String; let tokens: [Int64] }
    func testPronunciationAndTokenizationMatchDesktop() throws {
        let root = Bundle(for: VoiceEngine.self).resourceURL!.appendingPathComponent("Assets")
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: root.appendingPathComponent("phoneme-tests.json")))
        let frontend = try Phonemizer(root: root)
        for row in fixtures {
            XCTAssertEqual(try frontend.phonemes(row.text), row.phones, row.text)
            XCTAssertEqual(try frontend.tokens(for: row.phones), row.tokens, row.text)
        }
        XCTAssertThrowsError(try frontend.phonemes("bad\0input"))
        XCTAssertThrowsError(try frontend.chunks("  "))
    }
    func testNonDemoSentenceCanUseAllVoices() throws {
        let root = Bundle(for: VoiceEngine.self).resourceURL!.appendingPathComponent("Assets")
        let frontend = try Phonemizer(root: root)
        let tokens = try frontend.tokens(for: frontend.phonemes("Mau đưa cô ấy ra ngoài."))
        let engine = try VoiceEngine(root: root)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        XCTAssertNotEqual(tokens, engine.calibration.tokens)
        for voice in VoicePresets.names.indices {
            let audio = try engine.synthesize(voice: voice, tokens: tokens, maxFrames: 180, requireEnd: true, cancelled: { false }, progress: { _ in })
            XCTAssertGreaterThan(audio.count, 4800)
            XCTAssertTrue(audio.allSatisfy(\.isFinite))
            let cleaned = Dubbing.clean(audio, reduceHiss: true)
            let wave = folder.appendingPathComponent("voice-\(voice).wav")
            try Dubbing.write(cleaned, to: wave)
            let cue = Subtitle(start: 0.2, end: 0.7, text: "Mau đưa cô ấy ra ngoài.")
            let timeline = try Dubbing.schedule([cue], files: [wave], seconds: [Double(cleaned.count) / 48000], duration: 1)
            XCTAssertEqual(timeline.plans[0].speed, 1)
            let stem = try VoiceStem.create(timeline, folder: folder)
            let file = try AVAudioFile(forReading: stem)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
            try file.read(into: buffer)
            let offset = Int((cue.start * 48000).rounded())
            guard Int(buffer.frameLength) >= offset + cleaned.count else { XCTFail("Voice ending missing from stem"); continue }
            let channel = try XCTUnwrap(buffer.floatChannelData)[0]
            var squaredError = 0.0
            for index in cleaned.indices {
                let difference = Double(channel[offset + index] - cleaned[index])
                squaredError += difference * difference
            }
            let error = sqrt(squaredError / Double(cleaned.count))
            XCTAssertLessThan(error, 0.000001, "Natural-speed voice must not be time-stretched or cut")
            print("NATURAL VOICE \(voice + 1): \(cleaned.count) frames preserved; RMS error \(error)")
        }
    }
}

