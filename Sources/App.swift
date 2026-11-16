import SwiftUI
import AVFoundation
import UIKit

@MainActor
final class VoiceCheck: ObservableObject {
    @Published var status = "Chọn một giọng để kiểm tra khả năng tạo tiếng trực tiếp trên iPhone."
    @Published var busy = false
    @Published var output: URL?
    private var player: AVAudioPlayer?
    private var work: Task<Void, Never>?

    func start(_ voice: Int) {
        guard !busy else { return }
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("Assets") else {
            status = "Thiếu tài nguyên ứng dụng."; return
        }
        player?.stop()
        output = nil
        busy = true
        status = "Đang nạp giọng đã chọn trên iPhone…"
        UIApplication.shared.isIdleTimerDisabled = true
        let started = Date()
        work = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let samples = try autoreleasepool {
                    let engine = try VoiceEngine(root: root)
                    return try engine.synthesize(voice: voice, cancelled: { Task.isCancelled }) { frame in
                        if frame % 10 == 0 {
                            Task { @MainActor [weak self] in self?.status = "Đang tạo giọng \(voice + 1) · \(frame) khung âm thanh…" }
                        }
                    }
                }
                try Task.checkCancellation()
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("VietVideo-voice-\(voice + 1).wav")
                let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 1, interleaved: false)!
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
                    throw VoiceError.invalid("Không đủ bộ nhớ để ghi mẫu giọng.")
                }
                buffer.frameLength = AVAudioFrameCount(samples.count)
                samples.withUnsafeBufferPointer { ptr in
                    buffer.floatChannelData![0].update(from: ptr.baseAddress!, count: samples.count)
                }
                do {
                    let file = try AVAudioFile(forWriting: url, settings: format.settings)
                    try file.write(from: buffer)
                }
                await self?.finish(url: url, elapsed: Date().timeIntervalSince(started), seconds: Double(samples.count) / 48000)
            } catch {
                await self?.failed(error)
            }
        }
    }

    private func finish(url: URL, elapsed: TimeInterval, seconds: Double) {
        busy = false
        UIApplication.shared.isIdleTimerDisabled = false
        output = url
        status = String(format: "Đã tạo %.1f giây âm thanh trong %.1f giây. Nghe mẫu giọng dùng để lồng tiếng cho video.", seconds, elapsed)
        play()
    }

    private func failed(_ error: Error) {
        busy = false
        UIApplication.shared.isIdleTimerDisabled = false
        status = error is CancellationError ? "Đã dừng kiểm tra." : "Chưa chạy được bộ giọng: \(error.localizedDescription)"
    }

    func stop() { work?.cancel(); player?.stop() }

    func play() {
        guard let output else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: output)
            player?.play()
        } catch { status = "Không phát được mẫu giọng: \(error.localizedDescription)" }
    }
}

struct VoiceCheckView: View {
    @EnvironmentObject var state: VoiceCheck
    @EnvironmentObject var store: ProjectStore

    var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Text("VietVideo trên iPhone").font(.largeTitle.bold())
                        Text("Nghe thử giọng lồng tiếng").font(.title2).foregroundStyle(.secondary)
                        Text("Bốn giọng chạy trực tiếp trên iPhone. Nghe câu mẫu rồi chọn giọng phù hợp trong mục lồng tiếng.")
                        Text("Câu mẫu: Xin chào, đây là giọng thuyết minh Việt Video.")
                            .padding().frame(maxWidth: .infinity, alignment: .leading)
                            .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                        ForEach(VoicePresets.names.indices, id: \.self) { index in
                            Button("Tạo mẫu · " + VoicePresets.names[index]) { state.start(index) }
                                .buttonStyle(StudioButton()).disabled(state.busy || store.busy)
                        }
                        if state.busy { ProgressView(); Button("Dừng") { state.stop() } }
                        Text(state.status).font(.callout).textSelection(.enabled)
                        if let output = state.output {
                            Button("Nghe lại") { state.play() }.buttonStyle(.bordered)
                            ShareLink("Gửi tệp mẫu để kiểm tra", item: output)
                        }
                        Text("Giữ ứng dụng mở khi tạo giọng. Mẫu này dùng bộ dữ liệu gốc, không dùng giọng đọc có sẵn của iOS.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }.padding(24)
                }
            }
    }
}


