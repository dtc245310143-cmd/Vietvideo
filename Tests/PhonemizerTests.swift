import XCTest
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
    func testNonDemoSentenceCanUseBothVoices() throws {
        let root = Bundle(for: VoiceEngine.self).resourceURL!.appendingPathComponent("Assets")
        let frontend = try Phonemizer(root: root)
        let tokens = try frontend.tokens(for: frontend.phonemes("Mau đưa cô ấy ra ngoài."))
        let engine = try VoiceEngine(root: root)
        XCTAssertNotEqual(tokens, engine.calibration.tokens)
        for voice in 0..<2 {
            let audio = try engine.synthesize(voice: voice, tokens: tokens, maxFrames: 100, requireEnd: true, cancelled: { false }, progress: { _ in })
            XCTAssertGreaterThan(audio.count, 4800)
            XCTAssertTrue(audio.allSatisfy(\.isFinite))
        }
    }
}
