import UIKit
import SwiftUI
import AVFoundation

enum Palette {
    static let background = Color(red: 0.035, green: 0.05, blue: 0.105)
    static let panel = Color(red: 0.075, green: 0.095, blue: 0.17)
    static let muted = Color(red: 0.59, green: 0.65, blue: 0.76)
    static let cyan = Color(red: 0.30, green: 0.90, blue: 0.85)
    static let purple = Color(red: 0.51, green: 0.39, blue: 0.98)
}
extension View {
    func studioPanel() -> some View {
        padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.06), lineWidth: 1))
    }
}
struct StudioButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).foregroundStyle(Palette.background)
            .frame(maxWidth: .infinity).padding(.vertical, 17)
            .background(LinearGradient(colors: [Palette.cyan, Color(red: 0.35, green: 0.75, blue: 0.99)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 18))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(enabled ? 1 : 0.35).animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
struct WorkStatus: View {
    @EnvironmentObject var store: ProjectStore
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if store.busy { ProgressView().tint(Palette.cyan) } else { Image(systemName: "info.circle.fill").foregroundStyle(Palette.cyan) }
            VStack(alignment: .leading, spacing: 10) {
                Text(store.status).font(.callout).textSelection(.enabled)
                if store.busy { Button("Dừng tác vụ") { store.stop() }.font(.callout.bold()).foregroundStyle(.red) }
            }
        }.studioPanel()
    }
}
struct MovieThumbnail: View {
    let project: VideoProject
    @State private var image: UIImage?
    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.purple.opacity(0.4), Palette.panel], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let image { Image(uiImage: image).resizable().scaledToFill() } else { Image(systemName: "film").font(.largeTitle).foregroundStyle(Palette.cyan) }
        }.clipped().task(id: project.id) {
            let url = ProjectDisk.folder(project.id).appendingPathComponent(project.movieName)
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width: 500, height: 500)
            if let result = try? await generator.image(at: .zero) { image = UIImage(cgImage: result.image) }
        }
    }
}

