import FolioStorage
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

struct AssetTray: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.accent) private var accent
    let store: CourseStore
    /// How a dragged asset is written from where the note sits, e.g. `assets/a.png` or `../assets/a.png`.
    let link: (URL) -> String
    let insert: (String) -> Void
    /// Bumped by the editor when a pasted or dropped image lands in `assets/`, which this tray doesn't see happen.
    var revision = 0
    @State private var files: [URL] = []
    @State private var targeted = false

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Space.s) {
                if files.isEmpty {
                    Label("Finder에서 이미지나 파일을 여기로 끌어 오면 노트 assets 폴더에 복사됩니다", systemImage: "square.and.arrow.down")
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .padding(.horizontal, Theme.Space.s)
                }
                ForEach(files, id: \.self) { file in
                    AssetTile(file: file)
                        .onTapGesture { insert(link(file)) }
                        .draggable(link(file)) { AssetTile(file: file).frame(width: 72) }
                        .help("끌어서 본문에 넣거나 눌러서 커서 자리에 넣기")
                        .contextMenu { Button("커서 자리에 넣기") { insert(link(file)) } }
                }
            }
            .padding(.horizontal, Theme.Space.xl)
            .padding(.vertical, Theme.Space.s)
        }
        .scrollIndicators(.never)
        .frame(height: files.isEmpty ? Theme.Size.rowHeight : 104)
        .background(targeted ? accent.tint : Theme.Palette.page.opacity(0.5))
        .overlay {
            if targeted {
                RoundedRectangle(cornerRadius: Theme.Radius.control)
                    .strokeBorder(accent.color, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .padding(Theme.Space.xs)
            }
        }
        .animation(.snappy(duration: 0.2), value: targeted)
        .animation(.snappy(duration: 0.25), value: files)
        .dropDestination(for: URL.self) { urls, _ in
            workspace.perform {
                for url in urls where url.isFileURL {
                    // Files handed over from outside the sandbox stay readable only inside this scope.
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    try store.addNoteAsset(url)
                }
            }
            files = store.noteAssets()
            return true
        } isTargeted: { targeted = $0 }
        .task(id: revision) { files = store.noteAssets() }
    }

    static func markdown(for file: URL, path: String) -> String {
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        let isImage = UTType(filenameExtension: file.pathExtension)?.conforms(to: .image) ?? false
        let name = file.deletingPathExtension().lastPathComponent
        return isImage ? "![\(name)](\(encoded))" : "[\(file.lastPathComponent)](\(encoded))"
    }
}

private struct AssetTile: View {
    let file: URL
    @State private var thumbnail: CGImage?
    @State private var hovering = false

    var body: some View {
        VStack(spacing: Theme.Space.xs) {
            Group {
                if let thumbnail {
                    Image(decorative: thumbnail, scale: 2).resizable().scaledToFill()
                } else {
                    Image(systemName: "doc").font(.title2).foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            .frame(width: 72, height: 56)
            .background(Theme.Palette.fill)
            .clipShape(.rect(cornerRadius: Theme.Radius.tile))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.tile).strokeBorder(Theme.Palette.lineSoft))
            Text(file.lastPathComponent)
                .font(Theme.Typeface.label.weight(.regular))
                .foregroundStyle(Theme.Palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 72)
        }
        .scaleEffect(hovering ? 1.06 : 1)
        .shadow(color: .black.opacity(hovering ? 0.18 : 0), radius: 6, y: 3)
        .animation(.snappy(duration: 0.18), value: hovering)
        .onHover { hovering = $0 }
        .pointingHand()
        .contentShape(.rect)
        .task(id: file) {
            let request = QLThumbnailGenerator.Request(fileAt: file, size: CGSize(width: 72, height: 56), scale: 2, representationTypes: .thumbnail)
            thumbnail = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).cgImage
        }
    }
}
