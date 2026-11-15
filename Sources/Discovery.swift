import SwiftUI
import WebKit

@MainActor
final class DiscoveryStore: ObservableObject {
    @Published var query = "AI 3D 动画 短剧"
    @Published var platform = VideoPlatform.youtube
    @Published var newest = false
    @Published var length = 0
    @Published var results: [SourceVideo] = []
    @Published var busy = false
    @Published var message = "Tìm theo từ khóa hoặc dán link video."
    private var task: Task<Void, Never>?
    private var page = 1
    func stop() { task?.cancel() }
    var filtered: [SourceVideo] {
        results.filter { item in
            switch length { case 1: return item.duration > 0 && item.duration < 240; case 2: return item.duration >= 240 && item.duration <= 1200; case 3: return item.duration > 1200; default: return true }
        }
    }
    func search(more: Bool = false) {
        guard !busy else { return }
        if !more { page = 1; results = [] } else { page += 1 }
        busy = true; message = "Đang tìm trên \(platform.rawValue)…"
        task = Task {
            defer { busy = false }
            do {
                let found = try await VideoSources.search(query, platform: platform, page: page, newest: newest)
                try Task.checkCancellation()
                add(found); message = "\(results.count) video. Nếu nguồn yêu cầu xác minh, mở trình duyệt của app."
            } catch { message = error is CancellationError ? "Đã dừng tìm." : error.localizedDescription }
        }
    }
    func add(_ found: [SourceVideo]) {
        var ids = Set(results.map(\.id))
        results += found.filter { ids.insert($0.id).inserted }
    }
}

struct BrowserSelection: Identifiable {
    let id = UUID()
    let url: URL
    let platform: VideoPlatform
}

struct DiscoveryView: View {
    @EnvironmentObject var source: DiscoveryStore
    @EnvironmentObject var store: ProjectStore
    @EnvironmentObject var voices: VoiceCheck
    @State private var link = ""
    @State private var browser: BrowserSelection?
    let openStudio: () -> Void
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Khám phá").font(.largeTitle.bold())
                    Text("Tìm câu chuyện tiếp theo của bạn.").foregroundStyle(Palette.muted)
                    VStack(spacing: 14) {
                        TextField("Dán link YouTube, Bilibili, Douyin", text: $link).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL).textFieldStyle(.roundedBorder)
                        HStack {
                            Button("Tải video") { store.download(link); openStudio() }.buttonStyle(.borderedProminent).tint(Palette.cyan).foregroundStyle(Palette.background).disabled(store.busy || voices.busy)
                            Button("Mở link") { do { let (p, u) = try VideoPlatform.identify(link); browser = BrowserSelection(url: u, platform: p) } catch { source.message = error.localizedDescription } }.buttonStyle(.bordered)
                        }
                    }.studioPanel()
                    VStack(alignment: .leading, spacing: 14) {
                        Picker("Nguồn", selection: $source.platform) { ForEach(VideoPlatform.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                        TextField("Từ khóa tìm kiếm", text: $source.query).textFieldStyle(.roundedBorder).onSubmit { find() }
                        HStack {
                            Toggle("Mới nhất", isOn: $source.newest)
                            Picker("Thời lượng", selection: $source.length) { Text("Tất cả").tag(0); Text("Dưới 4 phút").tag(1); Text("4–20 phút").tag(2); Text("Trên 20 phút").tag(3) }.labelsHidden()
                        }
                        Button { find() } label: { Label("Tìm video", systemImage: "magnifyingglass") }.buttonStyle(StudioButton()).disabled(source.busy)
                        Button("Mở trình duyệt · đăng nhập / xác minh") { browser = BrowserSelection(url: source.platform.searchURL(source.query, newest: source.newest), platform: source.platform) }.font(.callout)
                    }.studioPanel()
                    Text(source.message).font(.callout).foregroundStyle(Palette.muted)
                    if source.busy { ProgressView().tint(Palette.cyan); Button("Dừng tìm") { source.stop() } }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        ForEach(source.filtered) { video in
                            VStack(alignment: .leading, spacing: 10) {
                                ZStack(alignment: .bottomTrailing) {
                                    AsyncImage(url: video.thumbnail) { image in image.resizable().scaledToFill() } placeholder: { Rectangle().fill(Palette.purple.opacity(0.25)).overlay(Image(systemName: "play.rectangle").font(.largeTitle)) }.frame(height: 110).clipped()
                                    Text(video.clock).font(.caption.monospacedDigit()).padding(5).background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 7)).padding(6)
                                }.clipShape(RoundedRectangle(cornerRadius: 14))
                                Text(video.title).font(.subheadline.bold()).lineLimit(3).frame(height: 58, alignment: .top)
                                Text(video.platform.rawValue).font(.caption).foregroundStyle(Palette.muted)
                                HStack {
                                    Button("Tải") { store.download(video.url.absoluteString); openStudio() }.buttonStyle(.borderedProminent).tint(Palette.purple).disabled(store.busy || voices.busy)
                                    Button { browser = BrowserSelection(url: video.url, platform: video.platform) } label: { Image(systemName: "safari") }.buttonStyle(.bordered)
                                }
                            }.padding(10).background(Palette.panel, in: RoundedRectangle(cornerRadius: 20))
                        }
                    }
                    if source.platform == .bilibili && !source.results.isEmpty { Button("Xem thêm kết quả") { source.search(more: true) }.buttonStyle(.bordered).disabled(source.busy) }
                    if !source.results.isEmpty { Button("Xem thêm trong trình duyệt") { browser = BrowserSelection(url: source.platform.searchURL(source.query), platform: source.platform) } }
                    Text("Nguồn có thể yêu cầu đăng nhập hoặc xác minh. Trong trình duyệt, mở đúng video rồi bấm Tải từ link. Dữ liệu phiên chỉ dùng cho đúng nguồn.").font(.footnote).foregroundStyle(Palette.muted)
                }.padding(20)
            }.background(Palette.background).navigationBarTitleDisplayMode(.inline)
                .sheet(item: $browser) { selected in SourceBrowser(selection: selected, openStudio: { browser = nil; openStudio() }) }
        }
    }
    private func find() {
        if source.platform == .douyin { browser = BrowserSelection(url: source.platform.searchURL(source.query), platform: .douyin) }
        else { source.search() }
    }
}

@MainActor
final class BrowserState: NSObject, ObservableObject, WKNavigationDelegate {
    @Published var title = "Trình duyệt nguồn"
    @Published var address: URL
    let web = WKWebView(frame: .zero)
    init(url: URL) {
        address = url; super.init(); web.navigationDelegate = self
        web.customUserAgent = VideoSources.userAgent
        web.load(URLRequest(url: url))
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { address = webView.url ?? address; title = webView.title ?? "Video" }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let scheme = navigationAction.request.url?.scheme?.lowercased()
        decisionHandler(scheme == "https" || scheme == "about" ? .allow : .cancel)
    }
}
struct SourceWeb: UIViewRepresentable {
    @ObservedObject var state: BrowserState
    func makeUIView(context: Context) -> WKWebView { state.web }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
struct SourceBrowser: View {
    @EnvironmentObject var source: DiscoveryStore
    @EnvironmentObject var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var browser: BrowserState
    let selection: BrowserSelection
    let openStudio: () -> Void
    init(selection: BrowserSelection, openStudio: @escaping () -> Void) {
        self.selection = selection; self.openStudio = openStudio
        _browser = StateObject(wrappedValue: BrowserState(url: selection.url))
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text(browser.address.host ?? "").font(.caption).foregroundStyle(.secondary).padding(6)
                SourceWeb(state: browser)
                VStack(spacing: 8) {
                    HStack {
                        Button { browser.web.goBack() } label: { Image(systemName: "chevron.left") }
                        Button { browser.web.goForward() } label: { Image(systemName: "chevron.right") }
                        Spacer()
                        Button("Lấy danh sách") { Task { await harvest() } }
                    }.padding(.horizontal, 8)
                    HStack {
                        Button("Tải từ link") { store.download(browser.address.absoluteString); openStudio() }.buttonStyle(.borderedProminent)
                        Button("Video đang phát") {
                            Task {
                                do {
                                    let (platform, _) = try VideoPlatform.identify(browser.address.absoluteString)
                                    let raw = try await browser.web.evaluateJavaScript("document.querySelector('video')?.currentSrc || ''") as? String ?? ""
                                    let media = URL(string: raw).flatMap { VideoPlatform.belongs($0, to: platform.mediaDomains) ? $0 : nil }
                                    store.download(browser.address.absoluteString, directMedia: media, title: browser.title); openStudio()
                                } catch { source.message = error.localizedDescription }
                            }
                        }.buttonStyle(.bordered)
                    }.disabled(store.busy)
                }.padding(12).background(Palette.panel)
            }.navigationTitle(selection.platform.rawValue).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Xong") { dismiss() } } }
        }
    }
    private func harvest() async {
        do {
            _ = try VideoPlatform.identify(browser.address.absoluteString)
            let script = """
            Array.from(document.querySelectorAll('a[href]')).filter(a=>/\\/video\\/|watch\\?v=|\\/shorts\\//.test(a.href)).slice(0,100).map(a=>({url:a.href,title:a.innerText||a.getAttribute('title')||a.querySelector('img')?.alt||'Video',image:a.querySelector('img')?.src||'',duration:(a.innerText.match(/\\d{1,2}:\\d{2}(?::\\d{2})?/)||[''])[0]}))
            """
            let rows = try await browser.web.evaluateJavaScript(script) as? [[String: Any]] ?? []
            let videos = rows.compactMap { row -> SourceVideo? in
                guard let raw = row["url"] as? String, let (platform, url) = try? VideoPlatform.identify(raw) else { return nil }
                let image = (row["image"] as? String).flatMap(URL.init(string:))
                return SourceVideo(title: row["title"] as? String ?? "Video", url: url, thumbnail: image?.scheme == "https" ? image : nil, duration: VideoSources.seconds(row["duration"] as? String ?? ""), platform: platform)
            }
            source.add(videos); source.message = "Đã lấy \(videos.count) mục từ trang đang mở."
            dismiss()
        } catch { source.message = error.localizedDescription }
    }
}

