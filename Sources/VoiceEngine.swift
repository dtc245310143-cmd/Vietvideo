import Foundation
import Accelerate
import onnxruntime_objc

struct Calibration: Decodable {
    struct Voice: Decodable { let anchor: [Float]; let referenceCodes: [[Int64]]; let identity: String? }
    let sample: String
    let tokens: [Int64]
    let voices: [Voice]
    let hidden, channels, layers, localLayers, localHeads, localHeadSize: Int
    let startToken, endToken, styleToken, promptStart, promptEnd, referenceToken: Int64
    let vocab, audioVocab: Int
}

enum VoiceError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

// The same ONNX graphs and reference voices as the approved desktop version.
final class VoiceEngine {
    let calibration: Calibration
    private let environment: ORTEnv
    private let prefill, decode, acoustic, codec: ORTSession
    private let textWeights, audioWeights: [Float]

    init(root: URL) throws {
        let calibrationRoot = root.appendingPathComponent("Calibration")
        calibration = try JSONDecoder().decode(Calibration.self, from: Data(contentsOf: calibrationRoot.appendingPathComponent("calibration.json")))
        let c = calibration
        guard c.hidden > 0, c.channels > 0, c.layers > 0, c.localLayers > 0,
              c.localHeads * c.localHeadSize == c.hidden, c.voices.count == VoicePresets.names.count,
              c.voices.allSatisfy({ $0.anchor.count == c.hidden && $0.referenceCodes.allSatisfy({ $0.count == c.channels }) })
        else { throw VoiceError.invalid("Dữ liệu giọng không hợp lệ.") }
        textWeights = try Self.readFloats(calibrationRoot.appendingPathComponent("text.f32"))
        audioWeights = try Self.readFloats(calibrationRoot.appendingPathComponent("audio.f32"))
        guard textWeights.count == c.vocab * c.hidden,
              audioWeights.count == c.channels * c.audioVocab * c.hidden
        else { throw VoiceError.invalid("Kích thước trọng số giọng không khớp.") }
        environment = try ORTEnv(loggingLevel: .warning)
        let options = try ORTSessionOptions()
        try options.setIntraOpNumThreads(2)
        try options.addConfigEntry(withKey: "session.intra_op.allow_spinning", value: "0")
        let models = root.appendingPathComponent("Models")
        prefill = try ORTSession(env: environment, modelPath: models.appendingPathComponent("vieneu_prefill.onnx").path, sessionOptions: options)
        decode = try ORTSession(env: environment, modelPath: models.appendingPathComponent("vieneu_decode_step.onnx").path, sessionOptions: options)
        acoustic = try ORTSession(env: environment, modelPath: models.appendingPathComponent("vieneu_acoustic_cached.onnx").path, sessionOptions: options)
        codec = try ORTSession(env: environment, modelPath: models.appendingPathComponent("moss_audio_tokenizer_decode_full.onnx").path, sessionOptions: options)
    }

    private static func readFloats(_ url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        guard data.count % 4 == 0 else { throw VoiceError.invalid("Tệp trọng số bị hỏng.") }
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    private func tensor<T>(_ values: [T], _ shape: [Int], _ type: ORTTensorElementDataType) throws -> ORTValue {
        guard shape.allSatisfy({ $0 >= 0 }), shape.reduce(1, *) == values.count else {
            throw VoiceError.invalid("Kích thước tensor không hợp lệ.")
        }
        let data = values.withUnsafeBytes { NSMutableData(bytes: $0.baseAddress, length: $0.count) }
        return try ORTValue(tensorData: data, elementType: type, shape: shape.map { NSNumber(value: $0) })
    }

    private func floats(_ value: ORTValue) throws -> [Float] {
        let info = try value.tensorTypeAndShapeInfo()
        guard info.elementType == .float else { throw VoiceError.invalid("Model trả sai loại dữ liệu.") }
        let data = try value.tensorData() as Data
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    private func run(_ session: ORTSession, _ inputs: [String: ORTValue]) throws -> [ORTValue] {
        let names = try session.outputNames()
        let outputs = try session.run(withInputs: inputs, outputNames: Set(names), runOptions: nil)
        return try names.map { name in
            guard let value = outputs[name] else { throw VoiceError.invalid("Thiếu đầu ra model: \(name)") }
            return value
        }
    }

    private func cachedInputs(_ outputs: [ORTValue], layers: Int) throws -> [String: ORTValue] {
        guard outputs.count >= 1 + layers * 2 else { throw VoiceError.invalid("Model thiếu bộ nhớ giải mã.") }
        var inputs: [String: ORTValue] = [:]
        for i in 0..<layers {
            inputs["past_k_\(i)"] = outputs[1 + i]
            inputs["past_v_\(i)"] = outputs[1 + layers + i]
        }
        return inputs
    }

    private func embed(_ token: Int64, _ codes: [Int64]?, _ anchor: [Float]) throws -> [Float] {
        let c = calibration
        guard token >= 0, token < c.vocab else { throw VoiceError.invalid("Token ngoài từ điển.") }
        var values = Array(textWeights[Int(token) * c.hidden..<(Int(token) + 1) * c.hidden])
        for i in 0..<c.hidden { values[i] += anchor[i] }
        if let codes = codes {
            guard codes.count == c.channels else { throw VoiceError.invalid("Số kênh mã giọng sai.") }
            for ch in 0..<c.channels {
                guard codes[ch] >= 0, codes[ch] < c.audioVocab else { throw VoiceError.invalid("Mã giọng không hợp lệ.") }
                let offset = (ch * c.audioVocab + Int(codes[ch])) * c.hidden
                for i in 0..<c.hidden { values[i] += audioWeights[offset + i] }
            }
        }
        return values
    }

    private func logits(_ vector: [Float], weights: [Float], offset: Int, count: Int) -> [Float] {
        var result = [Float](repeating: 0, count: count)
        weights.withUnsafeBufferPointer { w in
            vector.withUnsafeBufferPointer { v in
                result.withUnsafeMutableBufferPointer { out in
                    cblas_sgemv(CblasRowMajor, CblasNoTrans, Int32(count), Int32(calibration.hidden),
                                1, w.baseAddress! + offset, Int32(calibration.hidden), v.baseAddress!, 1,
                                0, out.baseAddress!, 1)
                }
            }
        }
        return result
    }

    private func sample(_ input: [Float], recent: [Int64]) throws -> Int64 {
        guard input.allSatisfy(\.isFinite) else { throw VoiceError.invalid("Model trả dữ liệu không hữu hạn.") }
        var scores = input
        for index in Set(recent) {
            let i = Int(index)
            scores[i] = scores[i] < 0 ? scores[i] * 1.2 : scores[i] / 1.2
        }
        let choices = scores.indices.sorted { scores[$0] > scores[$1] }.prefix(25)
        guard let first = choices.first else { throw VoiceError.invalid("Model không có mã giọng.") }
        let maximum = scores[first]
        let probabilities = choices.map { exp(Double((scores[$0] - maximum) / 0.8)) }
        let total = probabilities.reduce(0, +)
        var candidates: [(Int, Double)] = []
        var cumulative = 0.0
        for (i, probability) in zip(choices, probabilities) {
            candidates.append((i, probability))
            cumulative += probability
            if cumulative >= total * 0.95 { break }
        }
        let sum = candidates.reduce(0) { $0 + $1.1 }
        var random = Double.random(in: 0..<sum)
        for (index, probability) in candidates {
            random -= probability
            if random <= 0 { return Int64(index) }
        }
        return Int64(candidates.last!.0)
    }

    private func acousticFrame(_ condition: [Float], history: inout [[Int64]]) throws -> ([Int64], Bool) {
        let c = calibration
        let start = Array(textWeights[Int(c.startToken) * c.hidden..<(Int(c.startToken) + 1) * c.hidden])
        var inputs = ["token_emb": try tensor(condition + start, [1, 2, c.hidden], .float),
                      "position_ids": try tensor([Int64(0), 1], [1, 2], .int64)]
        for i in 0..<c.localLayers {
            inputs["past_k_\(i)"] = try tensor([Float](), [1, c.localHeads, 0, c.localHeadSize], .float)
            inputs["past_v_\(i)"] = try tensor([Float](), [1, c.localHeads, 0, c.localHeadSize], .float)
        }
        var out = try run(acoustic, inputs)
        var hidden = try floats(out[0])
        guard hidden.count == c.hidden * 2 else { throw VoiceError.invalid("Đầu ra acoustic không khớp.") }
        let endScores = logits(Array(hidden.prefix(c.hidden)), weights: textWeights, offset: 0, count: c.vocab)
        let ended = endScores.indices.max(by: { endScores[$0] < endScores[$1] }) == Int(c.endToken)
        var codes: [Int64] = []
        for channel in 0..<c.channels {
            let vector = channel == 0 ? Array(hidden.suffix(c.hidden)) : hidden
            let scores = logits(vector, weights: audioWeights, offset: channel * c.audioVocab * c.hidden, count: c.audioVocab)
            let code = try sample(scores, recent: history[channel])
            codes.append(code)
            history[channel].append(code)
            if history[channel].count > 64 { history[channel].removeFirst() }
            if channel + 1 < c.channels {
                var next = try cachedInputs(out, layers: c.localLayers)
                let offset = (channel * c.audioVocab + Int(code)) * c.hidden
                let embedding = Array(audioWeights[offset..<offset + c.hidden])
                next["token_emb"] = try tensor(embedding, [1, 1, c.hidden], .float)
                next["position_ids"] = try tensor([Int64(channel + 2)], [1, 1], .int64)
                out = try run(acoustic, next)
                hidden = try floats(out[0])
                guard hidden.count == c.hidden else { throw VoiceError.invalid("Đầu ra acoustic sai chiều.") }
            }
        }
        return (codes, ended)
    }

    func synthesize(voice: Int, tokens inputTokens: [Int64]? = nil, maxFrames: Int = 180, requireEnd: Bool = false, cancelled: () -> Bool, progress: (Int) -> Void) throws -> [Float] {
        try autoreleasepool {
            try synthesizeBuffers(voice: voice, tokens: inputTokens, maxFrames: maxFrames, requireEnd: requireEnd, cancelled: cancelled, progress: progress)
        }
    }
    private func synthesizeBuffers(voice: Int, tokens inputTokens: [Int64]?, maxFrames: Int, requireEnd: Bool, cancelled: () -> Bool, progress: (Int) -> Void) throws -> [Float] {
        let c = calibration
        guard c.voices.indices.contains(voice), maxFrames > 0, maxFrames <= 300 else {
            throw VoiceError.invalid("Chọn giọng hoặc độ dài không hợp lệ.")
        }
        let selected = c.voices[voice]
        let tokens = [c.styleToken, c.promptStart] + (inputTokens ?? c.tokens) + [c.promptEnd]
        var embeddings: [Float] = []
        for token in tokens { embeddings += try embed(token, nil, selected.anchor) }
        for codes in selected.referenceCodes { embeddings += try embed(c.referenceToken, codes, selected.anchor) }
        let length = embeddings.count / c.hidden
        var outputs = try run(prefill, ["inputs_embeds": try tensor(embeddings, [1, length, c.hidden], .float)])
        var hidden = Array(try floats(outputs[0]).suffix(c.hidden))
        var history = [[Int64]](repeating: [], count: c.channels)
        var frames: [Int32] = []
        var completed = false
        for frame in 0..<maxFrames {
            let ended = try autoreleasepool { () throws -> Bool in
                if cancelled() { throw CancellationError() }
                let (codes, ended) = try acousticFrame(hidden, history: &history)
                frames += codes.map(Int32.init)
                progress(frame + 1)
                if ended { return true }
                var next = try cachedInputs(outputs, layers: c.layers)
                next["inputs_embeds"] = try tensor(embed(c.startToken, codes, selected.anchor), [1, 1, c.hidden], .float)
                next["position_ids"] = try tensor([Int64(length + frame)], [1, 1], .int64)
                outputs = try run(decode, next)
                hidden = try floats(outputs[0])
                guard hidden.count == c.hidden else { throw VoiceError.invalid("Đầu ra giải mã không khớp.") }
                return false
            }
            if ended { completed = true; break }
        }
        if cancelled() { throw CancellationError() }
        if requireEnd && !completed { throw VoiceError.invalid("Giọng chưa kết thúc câu tự nhiên. Hãy thử lại; tool không cắt mất phần lời còn lại.") }
        let count = frames.count / c.channels
        let decoded = try run(codec, ["audio_codes": try tensor(frames, [1, count, c.channels], .int32),
                                      "audio_code_lengths": try tensor([Int32(count)], [1], .int32)])
        let shape = try decoded[0].tensorTypeAndShapeInfo().shape.map(\.intValue)
        let samples = try floats(decoded[0])
        guard shape.count == 3, shape[0] == 1, shape[1] > 0, shape[2] > 0,
              samples.count == shape[1] * shape[2] else { throw VoiceError.invalid("Âm thanh giải mã không hợp lệ.") }
        var mono = [Float](repeating: 0, count: shape[2])
        for channel in 0..<shape[1] {
            for i in 0..<shape[2] { mono[i] += samples[channel * shape[2] + i] / Float(shape[1]) }
        }
        guard mono.allSatisfy(\.isFinite), mono.contains(where: { abs($0) > 0.0001 }) else {
            throw VoiceError.invalid("Giọng tạo ra bị im lặng hoặc không hợp lệ.")
        }
        return mono
    }
}

