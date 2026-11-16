import XCTest
@testable import VietVideoVoiceCheck

final class VoiceEngineTests: XCTestCase {
    func testAllVoicesRunWithoutNetwork() throws {
        let bundle = Bundle(for: VoiceEngine.self)
        let root = try XCTUnwrap(bundle.resourceURL).appendingPathComponent("Assets")
        let engine = try VoiceEngine(root: root)
        XCTAssertEqual(engine.calibration.voices.count, VoicePresets.names.count)
        XCTAssertNotNil(engine.calibration.voices[0].identity)
        XCTAssertEqual(engine.calibration.voices[0].identity, engine.calibration.voices[1].identity)
        XCTAssertNotEqual(engine.calibration.voices[2].identity, engine.calibration.voices[3].identity)
        XCTAssertFalse(engine.calibration.voices[2].referenceCodes.isEmpty)
        XCTAssertFalse(engine.calibration.voices[3].referenceCodes.isEmpty)
        for voice in VoicePresets.names.indices {
            let samples = try engine.synthesize(voice: voice, maxFrames: 3, cancelled: { false }, progress: { _ in })
            XCTAssertGreaterThan(samples.count, 0)
            XCTAssertTrue(samples.allSatisfy(\.isFinite))
            XCTAssertTrue(samples.contains { abs($0) > 0.0001 })
        }
        XCTAssertThrowsError(try engine.synthesize(voice: VoicePresets.names.count, cancelled: { false }, progress: { _ in }))
        XCTAssertThrowsError(try engine.synthesize(voice: 0, cancelled: { true }, progress: { _ in }))
    }
}


