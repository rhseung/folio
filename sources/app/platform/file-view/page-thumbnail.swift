import SwiftUI

struct PageThumbnail: View {
    let thumbnails: PageThumbnails
    let page: Int
    let current: Bool
    var picked = false
    let box: CGSize
    @State private var image: CGImage?
    @Environment(\.accent) private var accent

    var body: some View {
        VStack(spacing: Theme.Space.xxs) {
            Group {
                if let image {
                    Image(decorative: image, scale: 1).resizable()
                } else {
                    Theme.Palette.fill
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(.rect(cornerRadius: Theme.Radius.small))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.small).strokeBorder(
                    picked ? accent.color : Theme.Palette.lineSoft, lineWidth: picked ? 2 : 1)
            )
            .frame(height: box.height)
            Text("\(page)").font(picked || current ? Theme.Typeface.label : Theme.Typeface.label.weight(.regular)).monospacedDigit()
                .foregroundStyle(picked ? accent.ink : current ? Theme.Palette.text : Theme.Palette.textTertiary)
        }
        .padding(.vertical, Theme.Space.s)
        .background {
            if current {
                RoundedRectangle(cornerRadius: Theme.Radius.strip)
                    .fill(Theme.Palette.currentPage)
                    .padding(.horizontal, -Theme.Space.s)
            }
        }
        .task(id: page) { image = await thumbnails.image(page) }
    }

    private var size: CGSize {
        guard let image, image.width > 0, image.height > 0 else { return box }
        let scale = min(box.width / CGFloat(image.width), box.height / CGFloat(image.height))
        return CGSize(width: (CGFloat(image.width) * scale).rounded(), height: (CGFloat(image.height) * scale).rounded())
    }
}
