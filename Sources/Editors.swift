import UIKit
import SwiftUI
import AVFoundation

struct MaskEditor: View {
    @EnvironmentObject var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var region = MaskRegion(x: 0.05, y: 0.78, width: 0.9, height: 0.14)
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Kéo trên ảnh để khoanh vùng chữ gốc cần làm mờ.").font(.callout).foregroundStyle(Palette.muted).padding(.horizontal)
                GeometryReader { geometry in
                    if let image {
                        let ratio = image.size.width / image.size.height
                        let width = min(geometry.size.width, geometry.size.height * ratio)
                        let height = width / ratio
                        ZStack(alignment: .topLeading) {
                            Image(uiImage: image).resizable().frame(width: width, height: height)
                            Rectangle().fill(Palette.cyan.opacity(0.25)).overlay(Rectangle().stroke(Palette.cyan, lineWidth: 2))
                                .frame(width: width * region.width, height: height * region.height)
                                .offset(x: width * region.x, y: height * region.y)
                        }.frame(width: width, height: height).contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 2).onChanged { value in
                                let x1 = max(0, min(1, value.startLocation.x / width)), y1 = max(0, min(1, value.startLocation.y / height))
                                let x2 = max(0, min(1, value.location.x / width)), y2 = max(0, min(1, value.location.y / height))
                                let selected = MaskRegion(x: min(x1,x2), y: min(y1,y2), width: abs(x1-x2), height: abs(y1-y2))
                                if selected.width > 0.01 && selected.height > 0.01 { region = selected }
                            })
                            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
                }.padding(.horizontal)
                HStack {
                    Button("Vùng dưới") { region = MaskRegion(x: 0.05, y: 0.78, width: 0.9, height: 0.14) }.buttonStyle(.bordered)
                    Button("Dùng vùng này") { store.settings.mask = region; store.saveDraft(); dismiss() }.buttonStyle(.borderedProminent).tint(Palette.cyan).foregroundStyle(Palette.background).disabled(image == nil)
                }.padding(.bottom)
            }.background(Palette.background).navigationTitle("Vùng chữ gốc").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Xong") { dismiss() } } }
                .task {
                    region = store.settings.mask ?? region
                    guard let project = store.current else { return }
                    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: ProjectDisk.folder(project.id).appendingPathComponent(project.movieName)))
                    generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width: 1000, height: 1000)
                    do { let result = try await generator.image(at: CMTime(seconds: min(1, project.duration / 2), preferredTimescale: 600)); image = UIImage(cgImage: result.image) }
                    catch { store.status = "Không lấy được ảnh xem trước: \(error.localizedDescription)"; dismiss() }
                }
        }
    }
}

struct DialogueEditor: View {
    @EnvironmentObject var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [Subtitle] = []
    @State private var error = ""
    var body: some View {
        NavigationStack {
            List {
                if !error.isEmpty { Text(error).foregroundStyle(.red) }
                ForEach(rows.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Câu \(i + 1)").font(.headline)
                            Spacer()
                            TextField("Từ", value: $rows[i].start, format: .number.precision(.fractionLength(1...3))).keyboardType(.decimalPad).frame(width: 70)
                            Text("→").foregroundStyle(Palette.muted)
                            TextField("Đến", value: $rows[i].end, format: .number.precision(.fractionLength(1...3))).keyboardType(.decimalPad).frame(width: 70)
                        }.font(.caption.monospacedDigit())
                        if !rows[i].source.isEmpty { Text(rows[i].source).font(.callout).foregroundStyle(Palette.muted) }
                        TextField("Lời Việt", text: $rows[i].text, axis: .vertical).lineLimit(2...8)
                    }.padding(.vertical, 8).listRowBackground(Palette.panel)
                }
            }.scrollContentBackground(.hidden).background(Palette.background)
                .navigationTitle("Lời gốc & lời Việt").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Đóng") { dismiss() } }
                    ToolbarItem(placement: .topBarTrailing) { Button("Lưu") {
                        do { try SRT.validate(rows, duration: store.current?.duration ?? 0); store.applyEdits(rows); dismiss() }
                        catch { self.error = error.localizedDescription }
                    } }
                }.onAppear {
                    guard let project = store.current else { return }
                    do {
                        rows = try SRT.parse(store.draft, duration: project.duration).map { cue in
                            var value = cue
                            if let old = project.cues.first(where: { abs($0.start - cue.start) < 0.002 && abs($0.end - cue.end) < 0.002 }) { value.source = old.source; value.speaker = old.speaker }
                            return value
                        }
                    } catch { self.error = error.localizedDescription }
                }
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject var store: ProjectStore
    @State private var deleting: VideoProject?
    let openStudio: () -> Void
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Dự án của bạn").font(.largeTitle.bold())
                    Text("Mở lại để tiếp tục dịch, hoặc xoá dự án để giải phóng dung lượng.").foregroundStyle(Palette.muted)
                    if store.projects.isEmpty { ContentUnavailableView("Chưa có dự án", systemImage: "film.stack", description: Text("Chọn video hoặc tìm video ở mục Khám phá.")) }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        ForEach(store.projects) { project in
                            VStack(alignment: .leading, spacing: 10) {
                                Button { store.open(project); openStudio() } label: {
                                    VStack(alignment: .leading, spacing: 10) {
                                        MovieThumbnail(project: project).frame(height: 110).clipShape(RoundedRectangle(cornerRadius: 14))
                                        Text(project.title).font(.subheadline.bold()).lineLimit(2).frame(height: 42, alignment: .top)
                                        HStack { Text("\(Int(project.duration)) giây"); Spacer(); Image(systemName: project.outputName == nil ? "doc.text" : "checkmark.circle.fill").foregroundStyle(Palette.cyan) }.font(.caption).foregroundStyle(Palette.muted)
                                    }
                                }.buttonStyle(.plain)
                                Button(role: .destructive) { deleting = project } label: {
                                    Label("Xoá dự án", systemImage: "trash").font(.caption.weight(.semibold))
                                        .foregroundStyle(.red).frame(maxWidth: .infinity).padding(.vertical, 10)
                                        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                                }.buttonStyle(.plain).accessibilityLabel("Xoá dự án \(project.title)")
                            }.padding(12).background(Palette.panel, in: RoundedRectangle(cornerRadius: 20)).disabled(store.busy)
                        }
                    }
                    Text(store.status).font(.footnote).foregroundStyle(Palette.muted)
                }.padding(20)
            }.background(Palette.background).navigationBarTitleDisplayMode(.inline)
                .alert("Xoá dự án?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { project in
                    Button("Xoá dự án", role: .destructive) { store.delete(project); deleting = nil }
                    Button("Huỷ", role: .cancel) { deleting = nil }
                } message: { project in
                    Text("Xoá “\(project.title)” cùng video, phụ đề và các tệp của dự án. Không thể hoàn tác. Video đã lưu ra Ảnh hoặc thư mục khác vẫn được giữ.")
                }
        }
    }
}

