import SwiftUI
import PhotosUI
import AVKit
import UniformTypeIdentifiers

@main
struct VietVideoApp: App {
    @StateObject private var store = ProjectStore()
    @StateObject private var voices = VoiceCheck()
    @StateObject private var source = DiscoveryStore()
    @Environment(\.scenePhase) private var phase
    @State private var tab = 0
    var body: some Scene {
        WindowGroup {
            TabView(selection: $tab) {
                StudioView(openSearch: { tab = 1 }).tabItem { Label("Studio", systemImage: "play.rectangle.fill") }.tag(0)
                DiscoveryView(openStudio: { tab = 0 }).tabItem { Label("Khám phá", systemImage: "magnifyingglass") }.tag(1)
                LibraryView(openStudio: { tab = 0 }).tabItem { Label("Dự án", systemImage: "square.stack.fill") }.tag(2)
                SettingsView().tabItem { Label("Cài đặt", systemImage: "slider.horizontal.3") }.tag(3)
            }.environmentObject(store).environmentObject(voices).environmentObject(source)
                .preferredColorScheme(.dark).tint(Palette.cyan)
                .onChange(of: phase) { value in if value == .background { store.background(); voices.stop(); source.stop() } }
        }
    }
}

struct StudioView: View {
    @EnvironmentObject var store: ProjectStore
    @EnvironmentObject var voices: VoiceCheck
    @AppStorage("geminiModel") private var model = "gemini-3.5-flash-lite"
    @AppStorage("sourceLanguage") private var language = "auto"
    @State private var files = false
    @State private var srtFile = false
    @State private var photo: PhotosPickerItem?
    @State private var logo: PhotosPickerItem?
    @State private var logoFile = false
    @State private var player: AVPlayer?
    @State private var repairStart = "30"
    @State private var repairEnd = "60"
    @State private var srtShare: URL?
    @State private var maskSheet = false
    @State private var dialogueSheet = false
    @State private var voiceSheet = false
    @FocusState private var editorFocused: Bool
    let openSearch: () -> Void
    private var busy: Bool { store.busy || voices.busy }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 14) {
                        Image("BrandMark").resizable().frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 17))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("VietVideo").font(.system(size: 30, weight: .bold, design: .rounded))
                            Text("Dịch · Lồng tiếng · Sáng tạo").font(.subheadline).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                    }.padding(.top, 8)
                    HStack(spacing: 8) {
                        step("1", "Video", complete: store.current != nil)
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Palette.muted)
                        step("2", "Lời Việt", complete: !store.draft.isEmpty)
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Palette.muted)
                        step("3", "Xuất", complete: store.output != nil)
                    }.padding(.vertical, 8)
                    HStack(spacing: 12) {
                        mode("Việt sub", subtitle: "Giữ tiếng gốc", icon: "captions.bubble.fill", dub: false)
                        mode("Lồng tiếng", subtitle: "Hai giọng Việt", icon: "waveform", dub: true)
                    }.disabled(busy)
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Nguồn video", systemImage: "film.stack").font(.headline)
                        HStack(spacing: 12) {
                            PhotosPicker(selection: $photo, matching: .videos) { Label("Ảnh", systemImage: "photo.on.rectangle") }
                            Button { files = true } label: { Label("Tệp", systemImage: "folder") }
                            Button(action: openSearch) { Label("Tìm video", systemImage: "magnifyingglass") }
                        }.buttonStyle(.bordered).controlSize(.large).disabled(busy)
                        if let project = store.current {
                            HStack { Text(project.title).font(.subheadline.bold()).lineLimit(2); Spacer(); Text(clock(project.duration)).font(.caption.monospacedDigit()).foregroundStyle(Palette.cyan) }
                            if let player { VideoPlayer(player: player).frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 16)) }
                        } else {
                            VStack(spacing: 12) { Image(systemName: "play.rectangle.on.rectangle").font(.system(size: 42)); Text("Bắt đầu với một câu chuyện hay.").font(.subheadline) }
                                .foregroundStyle(Palette.muted).frame(maxWidth: .infinity).padding(.vertical, 30)
                        }
                    }.studioPanel()
                    if store.current != nil {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack { Label("Lời Việt", systemImage: "text.bubble.fill").font(.headline); Spacer(); Button("Nhập SRT") { srtFile = true }.font(.callout) }
                            Button { player?.pause(); editorFocused = false; store.translate(key: APIKey.read(), model: model, language: language) } label: { Label("Nhận diện & dịch tiếng Việt", systemImage: "sparkles") }.buttonStyle(StudioButton())
                            if !store.draft.isEmpty {
                                Button { dialogueSheet = true } label: { Label("Sửa lời gốc / lời Việt", systemImage: "square.and.pencil") }.buttonStyle(.bordered).controlSize(.large)
                            }
                            DisclosureGroup("SRT và mốc thời gian") {
                                TextEditor(text: $store.draft).font(.system(.footnote, design: .monospaced)).scrollContentBackground(.hidden)
                                    .frame(minHeight: 230).padding(10).background(Palette.background, in: RoundedRectangle(cornerRadius: 14)).focused($editorFocused)
                                HStack {
                                    Button("Chuẩn bị SRT") { srtShare = store.shareSRT() }
                                    if let srtShare { ShareLink("Chia sẻ", item: srtShare) }
                                }.padding(.top, 10)
                            }
                            DisclosureGroup("Nhận diện lại đoạn thiếu") {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Nhập số giây. Kết quả rỗng được tự thử lại tối đa 3 lần; đoạn có tiếng nói nhỏ vẫn có thể cần kiểm tra.").font(.footnote).foregroundStyle(Palette.muted)
                                    HStack { Text("Từ"); TextField("30", text: $repairStart); Text("đến"); TextField("60", text: $repairEnd) }.keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                                    Button("Nhận diện và dịch lại") {
                                        guard let start = Double(repairStart.replacingOccurrences(of: ",", with: ".")), let end = Double(repairEnd.replacingOccurrences(of: ",", with: ".")) else { store.status = "Nhập mốc bắt đầu/kết thúc bằng số giây."; return }
                                        editorFocused = false; store.repair(start: start, end: end, key: APIKey.read(), model: model, language: language)
                                    }.buttonStyle(.bordered)
                                }.padding(.top, 8)
                            }
                            Text("Gemini cần Internet và dùng hạn mức key của bạn. Âm thanh sẽ gửi tới Google khi bạn bấm dịch.").font(.footnote).foregroundStyle(Palette.muted)
                        }.studioPanel().disabled(busy)
                        if store.settings.dub { soundPanel }
                        picturePanel
                        VStack(alignment: .leading, spacing: 14) {
                            Label("Sẵn sàng xuất bản", systemImage: "square.and.arrow.up.fill").font(.headline)
                            Text(store.settings.dub ? "Tiếng gốc cố định \(store.settings.originalVolume)% · Giọng \(store.settings.voice + 1)" : "Giữ nguyên mức tiếng gốc · Thêm phụ đề Việt").font(.callout).foregroundStyle(Palette.muted)
                            Button { player?.pause(); editorFocused = false; store.export() } label: {
                                Label(store.settings.dub ? "Xuất video lồng tiếng" : "Xuất video Việt sub", systemImage: "arrow.up.right.video.fill")
                            }.buttonStyle(StudioButton()).disabled(busy || store.draft.isEmpty)
                            if let output = store.output { ShareLink(item: output) { Label("Chia sẻ / lưu video đã xuất", systemImage: "square.and.arrow.up") }.buttonStyle(.bordered).controlSize(.large) }
                        }.studioPanel()
                    }
                    WorkStatus()
                    Text("Giữ ứng dụng mở khi xử lý. Giọng tạo trên iPhone; không cần máy tính làm máy chủ.").font(.footnote).foregroundStyle(Palette.muted)
                }.padding(20)
            }.background(Palette.background).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Xong") { editorFocused = false } } }
                .fileImporter(isPresented: $files, allowedContentTypes: [.movie], allowsMultipleSelection: false) { result in
                    do { if let url = try result.get().first { store.importMovie(url) } } catch { store.status = error.localizedDescription }
                }
                .fileImporter(isPresented: $srtFile, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
                    do {
                        guard let url = try result.get().first else { return }
                        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                        store.draft = try String(contentsOf: url, encoding: .utf8); store.saveDraft(); store.status = "Đã nhập phụ đề."
                    } catch { store.status = "Chưa đọc được SRT; chọn tệp UTF-8. \(error.localizedDescription)" }
                }
                .fileImporter(isPresented: $logoFile, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
                    do {
                        guard let url = try result.get().first else { return }
                        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                        store.addLogo(try Data(contentsOf: url))
                    } catch { store.status = error.localizedDescription }
                }
                .onChange(of: photo) { item in
                    guard let item else { return }
                    Task { do { if let movie = try await item.loadTransferable(type: ImportedMovie.self) { store.importMovie(movie.url, temporary: true) } } catch { store.status = error.localizedDescription }; photo = nil }
                }
                .onChange(of: logo) { item in
                    guard let item else { return }
                    Task { do { if let data = try await item.loadTransferable(type: Data.self) { store.addLogo(data) } } catch { store.status = error.localizedDescription }; logo = nil }
                }
                .onChange(of: store.draft) { _ in store.scheduleSave(); srtShare = nil }
                .onChange(of: store.settings) { _ in store.scheduleSave() }
                .task(id: store.current?.id) {
                    player?.pause()
                    if let project = store.current { player = AVPlayer(url: ProjectDisk.folder(project.id).appendingPathComponent(project.movieName)) }
                }
                .sheet(isPresented: $maskSheet) { MaskEditor() }
                .sheet(isPresented: $dialogueSheet) { DialogueEditor() }
                .sheet(isPresented: $voiceSheet) { VoiceCheckView() }
        }
    }
    private func clock(_ seconds: Double) -> String { String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60) }
    private func step(_ number: String, _ title: String, complete: Bool) -> some View {
        HStack(spacing: 7) { Image(systemName: complete ? "checkmark.circle.fill" : "\(number).circle.fill").foregroundStyle(complete ? Palette.cyan : Palette.muted); Text(title).font(.caption.bold()) }.frame(maxWidth: .infinity)
    }
    private func mode(_ title: String, subtitle: String, icon: String, dub: Bool) -> some View {
        Button { store.settings.dub = dub } label: {
            VStack(alignment: .leading, spacing: 9) { Image(systemName: icon).font(.title2); Text(title).font(.headline); Text(subtitle).font(.caption).foregroundStyle(Palette.muted) }
                .frame(maxWidth: .infinity, alignment: .leading).padding(17)
                .foregroundStyle(store.settings.dub == dub ? Palette.cyan : .white)
                .background(store.settings.dub == dub ? Palette.purple.opacity(0.2) : Palette.panel, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(store.settings.dub == dub ? Palette.cyan.opacity(0.8) : .white.opacity(0.06), lineWidth: 1))
        }.buttonStyle(.plain)
    }
    private var soundPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Label("Giọng lồng tiếng", systemImage: "waveform").font(.headline); Spacer(); Button("Nghe mẫu") { player?.pause(); voiceSheet = true }.font(.callout) }
            Picker("Chọn giọng", selection: $store.settings.voice) { Text("Giọng 1 · Mẫu ban đầu").tag(0); Text("Giọng 2 · Giảm vọng").tag(1) }.pickerStyle(.menu)
            Picker("Âm lượng tiếng gốc", selection: $store.settings.originalVolume) { ForEach([0,15,25,35,50,75,100], id: \.self) { Text("\($0)%").tag($0) } }
            Text("Mặc định 25%. Mức này giữ cố định từ đầu đến cuối, không tự to/nhỏ theo lời lồng tiếng.").font(.footnote).foregroundStyle(Palette.muted)
            Toggle("Kèm phụ đề Việt", isOn: $store.settings.burnSubtitles)
            Toggle("Giảm rè nhẹ cho giọng Việt", isOn: $store.settings.reduceHiss)
            Text("Câu dài được tự căn hình và tiếng, giữ cao độ và đủ lời.").font(.footnote).foregroundStyle(Palette.muted)
        }.studioPanel().disabled(busy)
    }
    private var picturePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Hình ảnh & phụ đề", systemImage: "wand.and.stars").font(.headline)
            if !store.settings.dub || store.settings.burnSubtitles {
                Picker("Cỡ chữ", selection: $store.settings.size) { Text("Nhỏ").tag(26.0); Text("Vừa").tag(30.0); Text("Lớn").tag(36.0) }.pickerStyle(.segmented)
                Toggle("Phụ đề phía trên", isOn: $store.settings.top)
                Toggle("Chữ vàng", isOn: $store.settings.yellow)
            }
            Divider()
            Toggle("Làm mờ chữ phụ đề gốc", isOn: Binding(get: { store.settings.mask != nil }, set: { enabled in
                store.settings.mask = enabled ? MaskRegion(x: 0.05, y: 0.78, width: 0.9, height: 0.14) : nil
                if enabled { maskSheet = true }
            }))
            if store.settings.mask != nil {
                Button("Chọn vùng chữ gốc / xem trước") { maskSheet = true }.buttonStyle(.bordered)
                Picker("Cách che", selection: $store.settings.solidMask) { Text("Làm mờ").tag(false); Text("Nền tối").tag(true) }.pickerStyle(.segmented)
                if !store.settings.solidMask { HStack { Text("Độ mờ"); Slider(value: $store.settings.blurStrength, in: 5...40, step: 1) } }
            }
            Divider()
            HStack { Label("Logo kênh", systemImage: "seal").font(.subheadline.bold()); Spacer(); PhotosPicker(selection: $logo, matching: .images) { Text("Chọn ảnh") }; Button("Tệp") { logoFile = true } }
            if store.settings.logoName != nil {
                Picker("Vị trí", selection: $store.settings.logoCorner) { Text("Trên trái").tag("topLeft"); Text("Trên phải").tag("topRight"); Text("Dưới trái").tag("bottomLeft"); Text("Dưới phải").tag("bottomRight") }
                HStack { Text("Cỡ \(Int(store.settings.logoWidth))%"); Slider(value: $store.settings.logoWidth, in: 5...30, step: 1) }
                Button("Bỏ logo khỏi video", role: .destructive) { store.settings.logoName = nil }
            }
        }.studioPanel().disabled(busy)
    }
}

