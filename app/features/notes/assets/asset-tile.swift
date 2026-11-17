import FolioDomain
import QuickLookThumbnailing
import SwiftUI

// `size`가 없으면 받은 폭을 채우고 4:3을 지킨다(iPhone 시트의 세 열 격자).
struct AssetTile: View {
    let model: AssetTrayModel
    let asset: NoteAsset
    var size: CGSize? = Theme.Size.assetTile
    var showsName = false
    @Environment(\.accent) private var accent
    @Environment(\.colorScheme) private var colorScheme
    @State private var quickLook: CGImage?

    var body: some View {
        sized
            .background(Theme.Palette.fill)
            .overlay(alignment: .topLeading) { badge }
            .overlay(alignment: .bottom) {
                if showsName { nameBand.transition(.move(edge: .bottom).combined(with: .opacity)) }
            }
            .clipShape(.rect(cornerRadius: Theme.Radius.control))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control).strokeBorder(Theme.Palette.lineSoft))
            .animation(Theme.Motion.quick, value: showsName)
    }

    // 썸네일이 있어도 파일이 바뀌면(`asset.modified`) 다시 받도록, 받는 일은 자리표시 대신 타일 전체에 붙인다.
    @ViewBuilder private var sized: some View {
        Group {
            if let size {
                thumbnail.frame(size)
            } else {
                Color.clear.aspectRatio(Theme.Size.assetTile.width / Theme.Size.assetTile.height, contentMode: .fit)
                    .overlay { thumbnail }
            }
        }
        .task(id: asset) { await loadQuickLook() }
    }

    @ViewBuilder private var thumbnail: some View {
        switch asset.kind {
        case .figure, .widget:
            if let request = model.thumbnail(asset, dark: colorScheme == .dark, accent: accent),
                let image = AssetThumbnails.shared.image(request)
            {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            } else {
                placeholder
            }
        case .image:
            if let quickLook {
                Image(decorative: quickLook, scale: 1).resizable().scaledToFill()
            } else {
                placeholder
            }
        case .file:
            // QuickLook은 문서의 첫 쪽을 종이 색 그대로 그리므로 다크에서도 흰 쪽으로 남는다.
            if let quickLook {
                Image(decorative: quickLook, scale: 1).resizable().scaledToFit().padding(Theme.Space.s)
            } else {
                placeholder
            }
        }
    }

    private var placeholder: some View {
        Image(systemName: AssetTrayModel.symbol(asset.kind))
            .font(Theme.Typeface.figureMedium)
            .foregroundStyle(Theme.Palette.textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
    }

    private var badge: some View {
        Image(systemName: AssetTrayModel.symbol(asset.kind))
            .font(Theme.Typeface.label)
            .foregroundStyle(Theme.Palette.textSecondary)
            .frame(width: Theme.Size.assetBadge, height: Theme.Size.assetBadge)
            .background(Theme.Palette.card.opacity(Theme.Opacity.veil), in: .rect(cornerRadius: Theme.Radius.small))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.small).strokeBorder(Theme.Palette.lineSoft))
            .padding(Theme.Space.xs)
            .accessibilityHidden(true)
    }

    private var nameBand: some View {
        FileName(model.name(asset), lineLimit: 1)
            .font(Theme.Typeface.label.weight(.regular))
            .foregroundStyle(Theme.Palette.text)
            .padding(.horizontal, Theme.Space.tight)
            .frame(maxWidth: .infinity, minHeight: Theme.Size.assetName, maxHeight: Theme.Size.assetName)
            .background(Theme.Palette.card.opacity(Theme.Opacity.veil))
    }

    private func loadQuickLook() async {
        guard asset.kind == .image || asset.kind == .file, let url = model.fileURL(asset) else { return }
        let side = size ?? Theme.Size.assetPreview
        let request = QLThumbnailGenerator.Request(fileAt: url, size: side, scale: 2, representationTypes: .thumbnail)
        quickLook = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).cgImage
    }
}
