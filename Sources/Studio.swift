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

@main
struct VietVideoApp: App {
    @StateObject private var store = ProjectStore()
    @StateObject private var voices = VoiceCheck()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            TabView {
                StudioView().tabItem { Label("Video", systemImage: "film") }
                VoiceCheckView().tabItem { Label("Hai giọng", systemImage: "waveform") }
                SettingsView().tabItem { Label("Cài đặt", systemImage: "gearshape") }
            }.environmentObject(store).environmentObject(voices)
                .onChange(of: phase) { value in if value == .background { store.background(); voices.stop() } }
        }
    }
}

struct StudioView: View {
    @EnvironmentObject var store: ProjectStore
    @EnvironmentObject var voices: VoiceCheck
    @AppStorage("geminiModel") private var model = "gemini-3.5-flash-lite"
    @AppStorage("sourceLanguage") private var language = "auto"
    @AppStorage("captionSize") private var fontSize = 30.0
    @AppStorage("captionTop") private var top = false
    @AppStorage("captionYellow") private var yellow = false
    @State private var files = false
    @State private var srtFile = false
    @State private var photo: PhotosPickerItem?
    @State private var player: AVPlayer?
    @State private var repairStart = "30"
    @State private var repairEnd = "60"
    @State private var srtShare: URL?
    private var busy: Bool { store.busy || voices.busy }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Việt sub trên iPhone").font(.largeTitle.bold())
                    Text("Bản iOS đang phát triển · chọn video trên máy, dịch và xuất MP4 giữ tiếng gốc.")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        PhotosPicker(selection: $photo, matching: .videos) { Label("Chọn từ Ảnh", systemImage: "photo.on.rectangle") }
                        Button { files = true } label: { Label("Chọn từ Tệp", systemImage: "folder") }
                    }.buttonStyle(.bordered).disabled(busy)
                    if !store.projects.isEmpty {
                        DisclosureGroup("Dự án đã lưu (\(store.projects.count))") {
                            ForEach(store.projects) { project in
                                Button { store.open(project) } label: {
                                    HStack { Text(project.title).lineLimit(1); Spacer(); Text("\(Int(project.duration)) giây").foregroundStyle(.secondary) }
                                }.padding(.vertical, 6).disabled(busy)
                            }
                        }
                    }
                    if let project = store.current {
                        Text(project.title).font(.headline).lineLimit(2)
                        if let player { VideoPlayer(player: player).frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 18)) }
                        HStack {
                            Button("Nhận diện & dịch Việt") { store.translate(key: APIKey.read(), model: model, language: language) }
                                .buttonStyle(.borderedProminent)
                            Button("Nhập SRT") { srtFile = true }.buttonStyle(.bordered)
                        }.disabled(busy)
                        Text("Nhận diện/dịch sẽ gửi âm thanh tới Gemini và dùng hạn mức của key. Video và dự án được lưu trên iPhone.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Text("Sửa phụ đề Việt").font(.headline)
                        TextEditor(text: $store.draft).font(.system(.footnote, design: .monospaced))
                            .frame(minHeight: 250).padding(8).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                            .disabled(busy).onChange(of: store.draft) { _ in store.scheduleSave(); srtShare = nil }
                        Button("Chuẩn bị tệp SRT") { srtShare = store.shareSRT() }.disabled(busy)
                        if let srtShare { ShareLink("Chia sẻ SRT", item: srtShare) }
                        DisclosureGroup("Nhận diện lại đoạn thiếu") {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Nhập số giây, ví dụ từ 30 đến 60. Đoạn không thấy thoại được tự thử lại tối đa 3 lần.").font(.footnote)
                                HStack { Text("Từ"); TextField("30", text: $repairStart); Text("đến"); TextField("60", text: $repairEnd) }
                                    .keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                                Button("Nhận diện và dịch lại khoảng này") {
                                    guard let start = Double(repairStart.replacingOccurrences(of: ",", with: ".")), let end = Double(repairEnd.replacingOccurrences(of: ",", with: ".")) else { store.status = "Nhập mốc bắt đầu và kết thúc bằng số giây."; return }
                                    store.repair(start: start, end: end, key: APIKey.read(), model: model, language: language)
                                }.buttonStyle(.bordered)
                            }.padding(.top, 8)
                        }.disabled(busy)
                        DisclosureGroup("Kiểu phụ đề") {
                            VStack {
                                Picker("Cỡ chữ", selection: $fontSize) { Text("Nhỏ").tag(26.0); Text("Vừa").tag(30.0); Text("Lớn").tag(36.0) }.pickerStyle(.segmented)
                                Toggle("Đặt phụ đề phía trên", isOn: $top)
                                Toggle("Chữ vàng", isOn: $yellow)
                            }.padding(.top, 8)
                        }.disabled(busy)
                        Button { player?.pause(); store.export(style: CaptionStyle(size: fontSize, top: top, yellow: yellow)) } label: {
                            Label("Xuất video Việt sub", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                        }.buttonStyle(.borderedProminent).disabled(busy || store.draft.isEmpty)
                        if let output = store.output { ShareLink("Chia sẻ video đã xuất", item: output).buttonStyle(.bordered) }
                    }
                    if store.busy { ProgressView(); Button("Dừng tác vụ") { store.stop() }.buttonStyle(.bordered) }
                    Text(store.status).font(.callout).textSelection(.enabled)
                    Text("Giữ ứng dụng mở trong lúc xử lý. Lồng tiếng cho nội dung bất kỳ, tìm/tải video từ link, làm mờ chữ và logo chưa có trong bản này.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(20)
            }.navigationTitle("VietVideo").navigationBarTitleDisplayMode(.inline)
                .fileImporter(isPresented: $files, allowedContentTypes: [.movie], allowsMultipleSelection: false) { result in
                    do { if let url = try result.get().first { store.importMovie(url) } } catch { store.status = error.localizedDescription }
                }
                .fileImporter(isPresented: $srtFile, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
                    do {
                        guard let url = try result.get().first else { return }
                        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                        store.draft = try String(contentsOf: url, encoding: .utf8)
                        store.saveDraft(); store.status = "Đã nhập SRT. Có thể sửa rồi xuất video."
                    } catch { store.status = "Chưa nhập được SRT; dùng tệp UTF-8. \(error.localizedDescription)" }
                }
                .onChange(of: photo) { item in
                    guard let item else { return }
                    Task {
                        do { if let movie = try await item.loadTransferable(type: ImportedMovie.self) { store.importMovie(movie.url, temporary: true) } }
                        catch { store.status = "Không đọc được video đã chọn: \(error.localizedDescription)" }
                        photo = nil
                    }
                }
                .task(id: store.current?.id) {
                    player?.pause()
                    if let project = store.current { player = AVPlayer(url: ProjectDisk.folder(project.id).appendingPathComponent(project.movieName)) }
                }
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
                Section("Lưu dữ liệu") {
                    Text("Dự án và video nằm trong Tệp → Trên iPhone → VietVideo. Dùng Chia sẻ video để chọn nơi lưu. API key nằm trong Keychain, không đi vào mã nguồn GitHub.")
                }
            }.navigationTitle("Cài đặt").onAppear { key = APIKey.read() }
        }
    }
}
