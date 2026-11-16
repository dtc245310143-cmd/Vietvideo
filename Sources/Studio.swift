import SwiftUI
import PhotosUI
import AVKit
import UniformTypeIdentifiers

private let languages: [(String, String)] = [("Tự nhận diện", "auto"), ("Tiếng Trung", "Chinese"), ("Tiếng Anh", "English"), ("Tiếng Nhật", "Japanese"), ("Tiếng Hàn", "Korean"), ("Tiếng Thái", "Thai"), ("Tiếng Việt", "Vietnamese"), ("Tiếng Pháp", "French"), ("Tiếng Đức", "German"), ("Tiếng Tây Ban Nha", "Spanish"), ("Tiếng Nga", "Russian"), ("Tiếng Indonesia", "Indonesian"), ("Tiếng Bồ Đào Nha", "Portuguese"), ("Tiếng Hindi", "Hindi"), ("Tiếng Ả Rập", "Arabic")]

struct ImportedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { SentTransferredFile($0.url) } importing: { received in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: url)
            return Self(url: url)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: ProjectStore
    @EnvironmentObject var voices: VoiceCheck
    @AppStorage("geminiModel") private var model = "gemini-3.5-flash-lite"
    @AppStorage("sourceLanguage") private var language = "auto"
    @State private var key = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("Gemini") {
                    SecureField("Gemini API key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Lưu API key trên iPhone") {
                        do { try APIKey.save(key); store.status = "Đã lưu key trong Keychain của iPhone." } catch { store.status = error.localizedDescription }
                    }
                    TextField("Model nhận diện / dịch", text: $model).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Picker("Ngôn ngữ nguồn", selection: $language) { ForEach(languages, id: \.1) { value in Text(value.0).tag(value.1) } }
                    Button("Kiểm tra kết nối") { store.checkKey(key: key, model: model, language: language) }
                    Link("Lấy Gemini API key", destination: URL(string: "https://aistudio.google.com/apikey")!)
                }.disabled(store.busy || voices.busy)
                Section { Text(store.status) }
                Section("VietVideo 1.0.4") {
                    Text("Bốn giọng chạy trực tiếp trên iPhone. Nhận diện/dịch dùng Gemini; tải video có thể yêu cầu đăng nhập nguồn.")
                }
                Section("Lưu dữ liệu") {
                    Text("Dự án và video nằm trong Tệp → Trên iPhone → VietVideo. Dùng Chia sẻ video để chọn nơi lưu. API key nằm trong Keychain, không đi vào mã nguồn GitHub.")
                }
            }.scrollContentBackground(.hidden).background(Palette.background).navigationTitle("Cài đặt").onAppear { key = APIKey.read() }
        }
    }
}

