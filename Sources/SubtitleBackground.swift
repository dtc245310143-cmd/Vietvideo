import Foundation

struct SubtitleBackground: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    static let yellow = Self(red: 1, green: 0.9, blue: 0)
    static let black = Self(red: 0, green: 0, blue: 0)
    var valid: Bool { [red, green, blue].allSatisfy { $0.isFinite && (0...1).contains($0) } }
    var usesDarkText: Bool {
        let linear = [red, green, blue].map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
        return (luminance + 0.05) / 0.05 >= 1.05 / (luminance + 0.05)
    }
}
