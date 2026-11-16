import XCTest
@testable import VietVideoVoiceCheck

final class DubbingTests: XCTestCase {
    func testLongSentencesStretchVideoWithoutDroppingWords() throws {
        let cues = [Subtitle(start: 0.2, end: 0.8, text: "Câu một"), Subtitle(start: 1, end: 1.5, text: "Câu hai")]
        let files = [URL(fileURLWithPath: "/one.wav"), URL(fileURLWithPath: "/two.wav")]
        let timeline = try Dubbing.schedule(cues, files: files, seconds: [3, 0.4], duration: 2)
        XCTAssertEqual(timeline.plans.map { $0.cue.text }, cues.map(\.text))
        XCTAssertEqual(timeline.stretches.count, 1)
        XCTAssertGreaterThan(timeline.duration, 2)
        XCTAssertEqual(timeline.plans[0].speed, 1)
        XCTAssertLessThanOrEqual(timeline.plans[0].seconds / timeline.plans[0].speed, timeline.plans[0].cue.end - timeline.plans[0].cue.start)
        XCTAssertLessThan(timeline.plans[0].cue.end, timeline.plans[1].cue.start)
        XCTAssertEqual(timeline.plans[1].cue.start - cues[1].start, timeline.duration - 2, accuracy: 0.0001)
    }
    func testSmallOverrunsStretchPicturesInsteadOfRushingSpeech() throws {
        let cues = [Subtitle(start: 0.2, end: 0.8, text: "Câu một"), Subtitle(start: 1, end: 1.5, text: "Câu hai")]
        let files = [URL(fileURLWithPath: "/one.wav"), URL(fileURLWithPath: "/two.wav")]
        let timeline = try Dubbing.schedule(cues, files: files, seconds: [0.75, 0.3], duration: 2)
        XCTAssertEqual(timeline.plans.map(\.speed), [1, 1])
        XCTAssertEqual(timeline.stretches.count, 1)
        XCTAssertGreaterThan(timeline.duration, 2)
        XCTAssertGreaterThanOrEqual(timeline.plans[0].cue.end - timeline.plans[0].cue.start, 0.75)
        XCTAssertLessThan(timeline.plans[0].cue.end, timeline.plans[1].cue.start)
        let short = try Dubbing.schedule(cues, files: files, seconds: [0.3, 0.3], duration: 2)
        XCTAssertEqual(short.plans.map(\.speed), [1, 1])
        XCTAssertTrue(short.stretches.isEmpty)
        XCTAssertEqual(short.duration, 2)
    }
    func testQuietFinalConsonantsSurviveCleanup() {
        var input = [Float](repeating: 0, count: 4800)
        input += (0..<24000).map { Float(sin(Double($0) * 2 * .pi * 180 / 48000) * 0.5) }
        input += (0..<8640).map { Float(sin(Double($0) * 2 * .pi * 3000 / 48000) * 0.002) }
        input += [Float](repeating: 0, count: 24000)
        for reduceHiss in [false, true] {
            let output = Dubbing.clean(input, reduceHiss: reduceHiss)
            guard output.count >= 35520 else { XCTFail("Quiet speech ending was cut"); continue }
            let tail = output[29760..<35520]
            let rms = sqrt(tail.reduce(Float(0)) { $0 + $1 * $1 } / Float(tail.count))
            XCTAssertGreaterThan(rms, 0.0008, "Quiet final consonants must remain audible")
            XCTAssertLessThan(output.count, input.count)
        }
    }
    func testCleanupBoundsSamplesAndKeepsAudibleSpeech() {
        var samples = [Float](repeating: 0, count: 9600)
        samples += (0..<24000).map { Float(sin(Double($0) * .pi * 2 * 880 / 48000) * 0.8) }
        samples += [Float](repeating: 0, count: 9600)
        let output = Dubbing.clean(samples, reduceHiss: true)
        XCTAssertGreaterThan(output.count, 24000)
        XCTAssertLessThan(output.count, samples.count)
        XCTAssertLessThanOrEqual(output.map { abs($0) }.max()!, 0.65001)
        XCTAssertEqual(output.first, 0); XCTAssertEqual(output.last, 0)
        XCTAssertTrue(Dubbing.clean([Float](repeating: 0, count: 4800), reduceHiss: true).isEmpty)
    }
    func testDefaultsAndInvalidCropOrVolumeAreRejected() throws {
        let settings = ExportSettings()
        XCTAssertEqual(settings.originalVolume, 25)
        try settings.validate()
        for index in VoicePresets.names.indices { var chosen = settings; chosen.voice = index; try chosen.validate() }
        var invalidVoice = settings; invalidVoice.voice = VoicePresets.names.count
        XCTAssertThrowsError(try invalidVoice.validate())
        for level in [0,15,25,35,50,75,100] { var chosen = settings; chosen.originalVolume = level; try chosen.validate() }
        var bad = settings; bad.originalVolume = 20; XCTAssertThrowsError(try bad.validate())
        bad = settings; bad.mask = MaskRegion(x: 0.8, y: 0.8, width: 0.3, height: 0.1); XCTAssertThrowsError(try bad.validate())
        bad = settings; bad.logoName = "../private.png"; XCTAssertThrowsError(try bad.validate())
    }
    func testSourceDomainsAndCookiesDoNotLeakToCDN() throws {
        XCTAssertThrowsError(try VideoPlatform.identify("https://youtube.com.attacker.test/watch?v=a"))
        XCTAssertThrowsError(try VideoPlatform.identify("https://youtube.com@attacker.test/video"))
        XCTAssertFalse(VideoPlatform.belongs(URL(string: "http://www.youtube.com/watch?v=a")!, to: VideoPlatform.youtube.domains))
        let cookie = HTTPCookie(properties: [.domain: ".bilibili.com", .path: "/", .name: "session", .value: "fake-value", .secure: "TRUE"])!
        let cdn = VideoSources.request(URL(string: "https://example.bilivideo.com/a.mp4")!, platform: .bilibili, cookies: [cookie])
        XCTAssertNil(cdn.value(forHTTPHeaderField: "Cookie"))
        let short = VideoSources.request(URL(string: "https://b23.tv/test")!, platform: .bilibili, cookies: [cookie])
        XCTAssertNil(short.value(forHTTPHeaderField: "Cookie"))
        let page = VideoSources.request(URL(string: "https://www.bilibili.com/video/BVabc")!, platform: .bilibili, cookies: [cookie])
        XCTAssertTrue(page.value(forHTTPHeaderField: "Cookie")?.contains("fake-value") == true)
        let youtube = VideoSources.request(URL(string: "https://www.youtube.com/results?search_query=test")!, platform: .youtube, cookies: [])
        XCTAssertTrue(youtube.value(forHTTPHeaderField: "User-Agent")?.contains("Windows") == true)
        let object = try VideoSources.json(after: "_ROUTER_DATA", in: "window._ROUTER_DATA = {\"text\":\"brace } and escaped \\\"\",\"value\":{\"n\":3}}; ignored();")
        XCTAssertEqual((object["value"] as? [String: Int])?["n"], 3)
    }
}

