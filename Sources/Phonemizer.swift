import Foundation

final class Phonemizer {
    private let handle: OpaquePointer
    private let vocabulary: [String: Int64]
    private let ranks: [String: Int]
    private let expression: NSRegularExpression
    private let byteMap: [UInt8: String]

    init(root: URL) throws {
        guard sea_g2p_abi_version() == 1 else { throw VoiceError.invalid("Bộ phát âm không đúng phiên bản.") }
        let dictionary = root.appendingPathComponent("Models/sea_g2p.bin").path
        guard let h = dictionary.withCString({ sea_g2p_open($0) }) else { throw VoiceError.invalid("Không nạp được từ điển phát âm tiếng Việt.") }
        do {
            let data = try Data(contentsOf: root.appendingPathComponent("Models/tokenizer.json"))
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let model = object?["model"] as? [String: Any], model["type"] as? String == "BPE",
                  let vocab = model["vocab"] as? [String: Int64], let merges = model["merges"] as? [[String]],
                  merges.allSatisfy({ $0.count == 2 }) else { throw VoiceError.invalid("Từ điển token không hợp lệ.") }
            vocabulary = vocab
            ranks = Dictionary(uniqueKeysWithValues: merges.enumerated().map { ($0.element[0] + "\0" + $0.element[1], $0.offset) })
            expression = try NSRegularExpression(pattern: "(?i:'s|'t|'re|'ve|'m|'ll|'d)|[^\\r\\n\\p{L}\\p{N}]?\\p{L}+|\\p{N}| ?[^\\s\\p{L}\\p{N}]+[\\r\\n]*|\\s*[\\r\\n]+|\\s+(?!\\S)|\\s+")
            let original = Array(33...126) + Array(161...172) + Array(174...255)
            var map: [UInt8: String] = [:]
            for byte in original { map[UInt8(byte)] = String(UnicodeScalar(byte)!) }
            var next = 256
            for byte in 0...255 where map[UInt8(byte)] == nil { map[UInt8(byte)] = String(UnicodeScalar(next)!); next += 1 }
            byteMap = map
            handle = h
        } catch { sea_g2p_close(h); throw error }
    }
    deinit { sea_g2p_close(handle) }

    func phonemes(_ text: String) throws -> String {
        guard !text.contains("\0"), text.count < 10000 else { throw VoiceError.invalid("Câu lồng tiếng quá dài hoặc chứa ký tự không hợp lệ.") }
        guard let output = text.withCString({ sea_g2p_phonemize(handle, $0, 1) }) else { throw VoiceError.invalid("Bộ phát âm chưa xử lý được câu này.") }
        defer { sea_g2p_string_free(output) }
        return String(cString: output).precomposedStringWithCanonicalMapping
    }

    func tokens(for phones: String) throws -> [Int64] {
        let text = phones.precomposedStringWithCanonicalMapping
        let ns = text as NSString
        var result: [Int64] = []
        for match in expression.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            var pieces = ns.substring(with: match.range).utf8.map { byteMap[$0]! }
            while pieces.count > 1 {
                var best: Int?, rank = Int.max
                for i in 0..<pieces.count - 1 {
                    if let value = ranks[pieces[i] + "\0" + pieces[i + 1]], value < rank { best = i; rank = value }
                }
                guard let i = best else { break }
                pieces[i] += pieces[i + 1]; pieces.remove(at: i + 1)
            }
            for piece in pieces {
                guard let token = vocabulary[piece] else { throw VoiceError.invalid("Có âm tiết chưa chuyển được sang bộ giọng.") }
                result.append(token)
            }
        }
        guard !result.isEmpty, result.count < 1500 else { throw VoiceError.invalid("Câu lồng tiếng trống hoặc quá dài.") }
        return result
    }

    func chunks(_ text: String) throws -> [[Int64]] {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { throw VoiceError.invalid("Câu lồng tiếng đang trống.") }
        var result: [[Int64]] = [], pending: [String] = []
        for word in words {
            pending.append(word)
            if pending.count >= 22 || (pending.count >= 5 && ".!?;".contains(word.last ?? " ")) {
                result.append(try tokens(for: phonemes(pending.joined(separator: " ")))); pending = []
            }
        }
        if !pending.isEmpty { result.append(try tokens(for: phonemes(pending.joined(separator: " ")))) }
        return result
    }
}
