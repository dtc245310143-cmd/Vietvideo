import XCTest
@testable import VietVideoVoiceCheck

final class CaptionSettingsTests: XCTestCase {
    func testOlderProjectsLoadAndCustomColorSurvivesSaving() throws {
        let settings = ExportSettings()
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        old.removeValue(forKey: "subtitleBackground")
        let restored = try JSONDecoder().decode(ExportSettings.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertNil(restored.subtitleBackground)
        XCTAssertEqual(restored, settings)
        for color in [SubtitleBackground.yellow, .black, SubtitleBackground(red: 0.2, green: 0.7, blue: 0.35)] {
            var chosen = settings
            chosen.subtitleBackground = color
            try chosen.validate()
            XCTAssertEqual(try JSONDecoder().decode(ExportSettings.self, from: JSONEncoder().encode(chosen)), chosen)
        }
    }
    func testTextContrastAndInvalidColors() throws {
        XCTAssertTrue(SubtitleBackground.yellow.usesDarkText)
        XCTAssertFalse(SubtitleBackground.black.usesDarkText)
        XCTAssertTrue(SubtitleBackground(red: 1, green: 1, blue: 1).usesDarkText)
        for component in [Double.nan, Double.infinity, -0.1, 1.1] {
            var settings = ExportSettings()
            settings.subtitleBackground = SubtitleBackground(red: component, green: 0, blue: 0)
            XCTAssertThrowsError(try settings.validate())
        }
    }
}
