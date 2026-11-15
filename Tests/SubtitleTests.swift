import XCTest
@testable import VietVideoVoiceCheck

final class SubtitleTests: XCTestCase {
    func testVietnameseRoundTripAndBOM() throws {
        let cues = [Subtitle(start: 0.125, end: 1.25, text: "Xin chào!\nBạn khỏe không?"), Subtitle(start: 2, end: 3.5, text: "Tôi ổn.")]
        let text = "\u{feff}" + SRT.encode(cues).replacingOccurrences(of: "\n", with: "\r\n")
        let parsed = try SRT.parse(text, duration: 4)
        XCTAssertEqual(parsed.map(\.text), cues.map(\.text))
        XCTAssertEqual(parsed.map(\.start), cues.map(\.start))
        XCTAssertEqual(parsed.map(\.end), cues.map(\.end))
        XCTAssertEqual(SRT.stamp(59.9996), "00:01:00,000")
    }
    func testRejectsOverlapOutOfVideoAndMissingText() {
        XCTAssertThrowsError(try SRT.parse("1\n00:00:00,000 --> 00:00:02,000\nA\n\n2\n00:00:01,000 --> 00:00:03,000\nB", duration: 4))
        XCTAssertThrowsError(try SRT.parse("1\n00:00:00,000 --> 00:00:06,000\nA", duration: 4))
        XCTAssertThrowsError(try SRT.parse("1\n00:00:00,000 --> 00:00:01,000\n", duration: 4))
        XCTAssertThrowsError(try SRT.time("00:00:nan"))
    }
    func testGeminiRelativeTimesAndEmptySpeech() throws {
        let json = Data("{\"segments\":[{\"start\":1,\"end\":2,\"source\":\"你好\",\"vietnamese\":\"Xin chào\",\"speaker\":\"one\"}]}".utf8)
        let rows = try Gemini.decode(json, duration: 10, offset: 30)
        XCTAssertEqual(rows[0].start, 31); XCTAssertEqual(rows[0].end, 32)
        XCTAssertEqual(rows[0].source, "你好")
        XCTAssertThrowsError(try Gemini.decode(json, duration: 1, offset: 0))
        XCTAssertTrue(try Gemini.decode(Data("{\"segments\":[]}".utf8), duration: 10, offset: 0).isEmpty)
    }
    func testPCMContainerAndStableCacheHash() {
        let data = Media.wav(Data(repeating: 0, count: 32000))
        XCTAssertEqual(data.count, 32044)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: data[8..<12], encoding: .ascii), "WAVE")
        XCTAssertEqual(Media.hash(data), Media.hash(data))
        XCTAssertNotEqual(Media.hash(data), Media.hash(Data()))
    }
}
