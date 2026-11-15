import XCTest
@testable import VietVideoVoiceCheck

final class VoiceEngineTests: XCTestCase {
    func testBothDesktopVoicesRunWithoutNetwork() throws {
        let bundle = Bundle(for: VoiceEngine.self)
        let root = try XCTUnwrap(bundle.resourceURL).appendingPathComponent("Assets")
        let engine = try VoiceEngine(root: root)
        XCTAssertEqual(engine.calibration.voices.count, 2)
        for voice in 0..<2 {
            let samples = try engine.synthesize(voice: voice, maxFrames: 3, cancelled: { false }, progress: { _ in })
            XCTAssertGreaterThan(samples.count, 0)
            XCTAssertTrue(samples.allSatisfy(\.isFinite))
            XCTAssertTrue(samples.contains { abs($0) > 0.0001 })
        }
        XCTAssertThrowsError(try engine.synthesize(voice: 3, cancelled: { false }, progress: { _ in }))
        XCTAssertThrowsError(try engine.synthesize(voice: 0, cancelled: { true }, progress: { _ in }))
    }
}

