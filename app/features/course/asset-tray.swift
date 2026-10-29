import QuickLookThumbnailing
import SwiftUI

struct AssetTray: View {
    @Environment(\.accent) private var accent
    let model: NoteEditorModel
    @State private var targeted = false

    var body: some View {
        let files = model.assets
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Space.s) {
                if files.isEmpty {
                    Label(.notesAssetsEmpty, systemImage: "square.and.arrow.down")
                        .font(Theme.Typeface.caption)
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .padding(.horizontal, Theme.Space.s)
                }
                ForEach(files, id: \.self) { file in
                    AssetTile(file: file)
                        .onTapGesture { model.pendingInsert = model.assetLink(file) }
                        .draggable(model.assetLink(file)) { AssetTile(file: file).frame(width: 72) }
                        .help(Text(.notesAssetsTileHelp))
                        .contextMenu { Button(.notesAssetsInsert) { model.pendingInsert = model.assetLink(file) } }
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
            model.addAssets(urls)
            return true
        } isTargeted: { targeted = $0 }
        .task(id: model.assetsRevision) { model.reloadAssets() }
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
