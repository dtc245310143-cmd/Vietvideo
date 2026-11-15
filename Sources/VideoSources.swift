import Foundation
import WebKit
import AVFoundation
import YouTubeKit

enum VideoPlatform: String, CaseIterable, Identifiable {
    case youtube = "YouTube", bilibili = "Bilibili", douyin = "Douyin"
    var id: String { rawValue }
    var domains: [String] {
        switch self { case .youtube: return ["youtube.com", "youtu.be"]; case .bilibili: return ["bilibili.com", "b23.tv"]; case .douyin: return ["douyin.com", "iesdouyin.com"] }
    }
    var mediaDomains: [String] {
        switch self {
        case .youtube: return domains + ["googlevideo.com", "youtube-nocookie.com"]
        case .bilibili: return domains + ["bilivideo.com", "bilivideo.cn", "bilivideo.net", "akamaized.net", "hdslb.com"]
        case .douyin: return domains + ["snssdk.com","amemv.com","douyinvod.com","bytecdn.cn","byteimg.com","pstatp.com","bytedance.com","ibytedtos.com","byteoversea.com","zjcdn.com"]
        }
    }
    func searchURL(_ query: String, newest: Bool = false) -> URL {
        var c = URLComponents(string: self == .youtube ? "https://www.youtube.com/results" : self == .bilibili ? "https://search.bilibili.com/all" : "https://www.douyin.com/search/" + query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)!
        c.queryItems = self == .youtube ? [URLQueryItem(name: "search_query", value: query), URLQueryItem(name: "sp", value: newest ? "CAISAhAB" : "EgIQAQ==")] : self == .bilibili ? [URLQueryItem(name: "keyword", value: query)] : [URLQueryItem(name: "type", value: "video")]
        return c.url!
    }
    static func belongs(_ url: URL, to domains: [String]) -> Bool {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil, let host = url.host?.lowercased() else { return false }
        return domains.contains { host == $0 || host.hasSuffix("." + $0) }
    }
    static func identify(_ input: String) throws -> (VideoPlatform, URL) {
        let expression = try NSRegularExpression(pattern: "https?://[^\\s<>]+")
        let ns = input as NSString
        guard let match = expression.firstMatch(in: input, range: NSRange(location: 0, length: ns.length)),
              let url = URL(string: ns.substring(with: match.range).trimmingCharacters(in: CharacterSet(charactersIn: "，。),;"))),
              let platform = allCases.first(where: { belongs(url, to: $0.domains) }) else { throw AppError.message("Dán link video YouTube, Bilibili hoặc Douyin.") }
        return (platform, url)
    }
}

struct SourceVideo: Identifiable, Equatable {
    var id: String { url.absoluteString }
    var title: String
    var url: URL
    var thumbnail: URL?
    var duration: Double = 0
    var platform: VideoPlatform
    var clock: String { duration > 0 ? String(format: "%d:%02d", Int(duration) / 60, Int(duration) % 60) : "Video" }
}

private final class SourceRedirects: NSObject, URLSessionTaskDelegate {
    let domains: [String]
    init(_ domains: [String]) { self.domains = domains }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, VideoPlatform.belongs(url, to: domains) else { completionHandler(nil); return }
        var next = request
        if request.url?.host != response.url?.host { next.setValue(nil, forHTTPHeaderField: "Cookie"); next.setValue(nil, forHTTPHeaderField: "Authorization") }
        completionHandler(next)
    }
}

enum VideoSources {
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Version/17.0 Mobile/15E148 Safari/604.1"
    static func seconds(_ text: String) -> Double { text.split(separator: ":").reduce(0) { $0 * 60 + (Double($1) ?? 0) } }
    static func clean(_ text: String) -> String { text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression).replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"") }
    static func json(after marker: String, in text: String) throws -> [String: Any] {
        guard let range = text.range(of: marker), let start = text[range.upperBound...].firstIndex(of: "{") else { throw AppError.message("Trang chưa trả dữ liệu video. Thử mở trong trình duyệt của app và xác minh nếu được yêu cầu.") }
        var depth = 0, quoted = false, escaped = false
        for i in text[start...].indices {
            let c = text[i]
            if quoted { if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { quoted = false } }
            else if c == "\"" { quoted = true }
            else if c == "{" { depth += 1 }
            else if c == "}" { depth -= 1; if depth == 0 { return try JSONSerialization.jsonObject(with: Data(text[start...i].utf8)) as? [String: Any] ?? [:] } }
        }
        throw AppError.message("Dữ liệu trang video chưa đầy đủ.")
    }
    static func objects(_ value: Any, key: String) -> [[String: Any]] {
        if let object = value as? [String: Any] {
            var rows = object[key].flatMap { $0 as? [String: Any] }.map { [$0] } ?? []
            for child in object.values { rows += objects(child, key: key) }; return rows
        }
        return (value as? [Any] ?? []).flatMap { objects($0, key: key) }
    }
    static func session(domains: [String]) -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 35; c.timeoutIntervalForResource = 1800; c.httpShouldSetCookies = false
        return URLSession(configuration: c, delegate: SourceRedirects(domains), delegateQueue: nil)
    }
    @MainActor static func cookies(_ platform: VideoPlatform) async -> [HTTPCookie] {
        let stored: [HTTPCookie] = await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
        return stored.filter { cookie in
            let host = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return platform.domains.contains { host == $0 || host.hasSuffix("." + $0) }
        }
    }
    static func request(_ url: URL, platform: VideoPlatform, cookies: [HTTPCookie]) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(platform.searchURL("").absoluteString, forHTTPHeaderField: "Referer")
        if VideoPlatform.belongs(url, to: platform.domains) {
            let host = url.host?.lowercased() ?? ""
            let matching = cookies.filter { cookie in
                let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
                return (host == domain || host.hasSuffix("." + domain)) && url.path.hasPrefix(cookie.path) && (cookie.expiresDate == nil || cookie.expiresDate! > Date())
            }
            for (key, value) in HTTPCookie.requestHeaderFields(with: matching) { request.setValue(value, forHTTPHeaderField: key) }
        }
        return request
    }
    static func page(_ url: URL, platform: VideoPlatform) async throws -> (String, URL) {
        guard VideoPlatform.belongs(url, to: platform.domains) else { throw AppError.message("Link trang không đúng nguồn.") }
        let session = session(domains: platform.domains)
        defer { session.invalidateAndCancel() }
        let stored = await cookies(platform)
        let request = request(url, platform: platform, cookies: stored)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count < 12_000_000,
              let text = String(data: data, encoding: .utf8) else { throw AppError.message("Nguồn video từ chối yêu cầu. Mở trình duyệt trong app để đăng nhập hoặc xác minh.") }
        return (text, response.url ?? url)
    }
    static func search(_ query: String, platform: VideoPlatform, page number: Int = 1, newest: Bool = false) async throws -> [SourceVideo] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        if platform == .douyin { return [] }
        if platform == .bilibili {
            var url = URLComponents(string: "https://api.bilibili.com/x/web-interface/search/type")!
            url.queryItems = [URLQueryItem(name: "search_type", value: "video"), URLQueryItem(name: "keyword", value: query), URLQueryItem(name: "page", value: String(number)), URLQueryItem(name: "order", value: newest ? "pubdate" : "totalrank")]
            let (text, _) = try await page(url.url!, platform: platform)
            let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
            guard let data = object?["data"] as? [String: Any], let rows = data["result"] as? [[String: Any]] else { throw AppError.message("Bilibili yêu cầu phiên trình duyệt. Mở Bilibili trong app rồi thử lại.") }
            return rows.compactMap { row in
                guard let bvid = row["bvid"] as? String else { return nil }
                let image = (row["pic"] as? String ?? "").replacingOccurrences(of: "http://", with: "https://")
                return SourceVideo(title: clean(row["title"] as? String ?? "Bilibili"), url: URL(string: "https://www.bilibili.com/video/\(bvid)")!, thumbnail: URL(string: image.hasPrefix("//") ? "https:" + image : image), duration: seconds(row["duration"] as? String ?? ""), platform: platform)
            }
        }
        let (text, _) = try await page(platform.searchURL(query, newest: newest), platform: platform)
        let object = try json(after: "ytInitialData", in: text)
        return objects(object, key: "videoRenderer").compactMap { row in
            guard let id = row["videoId"] as? String else { return nil }
            let title = ((row["title"] as? [String: Any])?["runs"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined()
            let image = (((row["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]])?.last)?["url"] as? String
            let length = (row["lengthText"] as? [String: Any])?["simpleText"] as? String ?? ""
            return SourceVideo(title: title, url: URL(string: "https://www.youtube.com/watch?v=\(id)")!, thumbnail: image.flatMap(URL.init(string:)), duration: seconds(length), platform: .youtube)
        }
    }

    static func downloadFile(_ url: URL, platform: VideoPlatform, into folder: URL, ext: String = "mp4") async throws -> URL {
        guard VideoPlatform.belongs(url, to: platform.mediaDomains) else { throw AppError.message("Địa chỉ tải không thuộc nguồn video được hỗ trợ.") }
        let session = session(domains: platform.mediaDomains); defer { session.invalidateAndCancel() }
        let stored = await cookies(platform)
        let request = request(url, platform: platform, cookies: stored)
        let (temporary, response) = try await session.download(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), !(http.mimeType ?? "").contains("text"), !(http.mimeType ?? "").contains("json") else { throw AppError.message("Nguồn yêu cầu đăng nhập/xác minh hoặc link tải đã hết hạn. Mở nguồn trong app và thử lại.") }
        try Task.checkCancellation()
        let file = folder.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        try FileManager.default.moveItem(at: temporary, to: file)
        return file
    }

    static func download(_ input: String, into folder: URL, log: @Sendable (String) -> Void) async throws -> (URL, String) {
        let (platform, original) = try VideoPlatform.identify(input)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        log("Đang lấy luồng \(platform.rawValue)…")
        if platform == .youtube {
            let saved = await cookies(platform)
            for cookie in saved { HTTPCookieStorage.shared.setCookie(cookie) }
            let video = YouTube(url: original, methods: [.local])
            let streams = try await video.streams.filter { $0.isNativelyPlayable && ($0.videoResolution ?? 0) <= 1080 }
            let metadata = try? await video.metadata
            let best = streams.filter { $0.includesVideoTrack && $0.fileExtension == .mp4 }.highestResolutionStream()
            if let stream = best, stream.includesVideoAndAudioTrack {
                try await stream.waitUntilAvailable()
                return (try await downloadFile(stream.url, platform: platform, into: folder), metadata?.title ?? "YouTube")
            }
            guard let image = best, let audio = streams.filterAudioOnly().filter({ $0.fileExtension == .m4a }).highestAudioBitrateStream() else { throw AppError.message("YouTube chưa cung cấp luồng phù hợp. Có thể cần xác minh trong trình duyệt của app.") }
            try await image.waitUntilAvailable(); try await audio.waitUntilAvailable()
            let v = try await downloadFile(image.url, platform: platform, into: folder)
            let a = try await downloadFile(audio.url, platform: platform, into: folder, ext: "m4a")
            return (try await mux(video: v, audio: a, folder: folder), metadata?.title ?? "YouTube")
        }
        let (_, resolved) = try await page(original, platform: platform)
        if platform == .douyin {
            let ns = resolved.absoluteString as NSString
            let regex = try NSRegularExpression(pattern: "(?:/video/|modal_id=|aweme_id=)([0-9]+)")
            guard let match = regex.firstMatch(in: resolved.absoluteString, range: NSRange(location: 0, length: ns.length)) else { throw AppError.message("Mở đúng video Douyin rồi chọn lấy video đang mở.") }
            let id = ns.substring(with: match.range(at: 1))
            let (html, _) = try await page(URL(string: "https://www.douyin.com/share/video/\(id)/")!, platform: platform)
            let data = try json(after: "_ROUTER_DATA", in: html)
            for info in objects(data, key: "videoInfoRes") {
                for row in info["item_list"] as? [[String: Any]] ?? [] where String(describing: row["aweme_id"] ?? "") == id {
                    guard let video = row["video"] as? [String: Any], let address = video["play_addr"] as? [String: Any], let list = address["url_list"] as? [String] else { continue }
                    for raw in list {
                        if let url = URL(string: raw), VideoPlatform.belongs(url, to: platform.mediaDomains) { return (try await downloadFile(url, platform: platform, into: folder), row["desc"] as? String ?? "Douyin") }
                    }
                }
            }
            throw AppError.message("Douyin yêu cầu cookies mới. Mở và phát đúng video trong trình duyệt của app rồi thử lại.")
        }
        let regex = try NSRegularExpression(pattern: "BV[A-Za-z0-9]+|av[0-9]+")
        let ns = resolved.path as NSString
        guard let match = regex.firstMatch(in: resolved.path, range: NSRange(location: 0, length: ns.length)) else { throw AppError.message("Không tìm thấy mã video Bilibili.") }
        let id = ns.substring(with: match.range)
        let argument = id.hasPrefix("BV") ? "bvid=\(id)" : "aid=\(id.dropFirst(2))"
        let (metadata, _) = try await page(URL(string: "https://api.bilibili.com/x/web-interface/view?\(argument)")!, platform: platform)
        let object = try JSONSerialization.jsonObject(with: Data(metadata.utf8)) as? [String: Any]
        guard let info = object?["data"] as? [String: Any], let firstCID = info["cid"] as? Int else { throw AppError.message("Không đọc được thông tin Bilibili; thử đăng nhập trong trình duyệt của app.") }
        let partNumber = Int(URLComponents(url: resolved, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "p" })?.value ?? "1") ?? 1
        let pages = info["pages"] as? [[String: Any]] ?? []
        guard partNumber > 0, partNumber == 1 || pages.indices.contains(partNumber - 1) else { throw AppError.message("Phần video Bilibili không tồn tại.") }
        let cid = pages.indices.contains(partNumber - 1) ? pages[partNumber - 1]["cid"] as? Int ?? firstCID : firstCID
        let (play, _) = try await page(URL(string: "https://api.bilibili.com/x/player/playurl?\(argument)&cid=\(cid)&qn=80&fnval=4048&fourk=0")!, platform: platform)
        let response = try JSONSerialization.jsonObject(with: Data(play.utf8)) as? [String: Any]
        let data = response?["data"] as? [String: Any] ?? [:]
        if let dash = data["dash"] as? [String: Any] {
            let videos = (dash["video"] as? [[String: Any]] ?? []).filter { (($0["codecs"] as? String ?? "").hasPrefix("avc")) && ($0["height"] as? Int ?? 0) <= 1080 }.sorted { ($0["height"] as? Int ?? 0) > ($1["height"] as? Int ?? 0) }
            let audios = (dash["audio"] as? [[String: Any]] ?? []).sorted { ($0["bandwidth"] as? Int ?? 0) > ($1["bandwidth"] as? Int ?? 0) }
            func address(_ item: [String: Any]?) -> URL? { (item?["baseUrl"] as? String ?? item?["base_url"] as? String).flatMap(URL.init(string:)) }
            if let v = address(videos.first), let a = address(audios.first) {
                let video = try await downloadFile(v, platform: platform, into: folder)
                let audio = try await downloadFile(a, platform: platform, into: folder, ext: "m4a")
                return (try await mux(video: video, audio: audio, folder: folder), info["title"] as? String ?? "Bilibili")
            }
        }
        let parts = data["durl"] as? [[String: Any]] ?? []
        guard parts.count == 1, let raw = parts[0]["url"] as? String, let url = URL(string: raw) else { throw AppError.message("Bilibili chưa trả luồng MP4 đầy đủ; tool không tải một phần video rồi báo thành công.") }
        return (try await downloadFile(url, platform: platform, into: folder), info["title"] as? String ?? "Bilibili")
    }

    static func mux(video: URL, audio: URL, folder: URL) async throws -> URL {
        let source = AVURLAsset(url: video), sound = AVURLAsset(url: audio)
        let composition = AVMutableComposition()
        let duration = try await source.load(.duration)
        guard let image = try await source.loadTracks(withMediaType: .video).first, let audio = try await sound.loadTracks(withMediaType: .audio).first,
              let v = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid), let a = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw AppError.message("Không ghép được luồng hình và tiếng.") }
        try v.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: image, at: .zero)
        v.preferredTransform = try await image.load(.preferredTransform)
        let audioDuration = try await sound.load(.duration)
        try a.insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeMinimum(duration, audioDuration)), of: audio, at: .zero)
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else { throw AppError.message("Không tạo được tệp tải về.") }
        let url = folder.appendingPathComponent("download.mp4")
        export.outputURL = url; export.outputFileType = .mp4
        await withTaskCancellationHandler(operation: { await export.export() }, onCancel: { export.cancelExport() })
        try Task.checkCancellation()
        guard export.status == .completed else { throw export.error ?? AppError.message("Ghép luồng chưa hoàn thành.") }
        return url
    }
}

