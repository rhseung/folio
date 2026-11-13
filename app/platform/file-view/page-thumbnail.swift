import SwiftUI

/// The current page's wash is grey, not the course's tint, so a current page that is also picked still reads as both,
/// and neither looks like the save row above a range.
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
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.small).strokeBorder(picked ? accent.color : Theme.Palette.lineSoft, lineWidth: picked ? 2 : 1))
            // Every page in a slot as tall as the box, so a column of wide slides doesn't shift as their images come in.
            .frame(height: box.height)
            Text("\(page)").font(picked || current ? Theme.Typeface.label : Theme.Typeface.label.weight(.regular)).monospacedDigit()
                .foregroundStyle(picked ? accent.ink : current ? Theme.Palette.text : Theme.Palette.textTertiary)
        }
        .padding(.vertical, Theme.Space.s)
        .background {
            // Sideways the wash reaches into the column's margins rather than padding the page in, so a strip of fixed
            // width keeps its pages as wide as they were. Its corner is the page's plus the reach, to run alongside it, and
            // a class's tint's, to sit in it as one shape.
            if current {
                RoundedRectangle(cornerRadius: Theme.Radius.strip)
                    .fill(Theme.Palette.currentPage)
                    .padding(.horizontal, -Theme.Space.s)
            }
        }
        .task(id: page) { image = await thumbnails.image(page) }
    }

    /// The page fitted into the box, so its ring and corners hug it: a wide slide comes out shorter, a portrait page
    /// narrower. Until it is drawn, the whole box.
    private var size: CGSize {
        guard let image, image.width > 0, image.height > 0 else { return box }
        let scale = min(box.width / CGFloat(image.width), box.height / CGFloat(image.height))
        return CGSize(width: (CGFloat(image.width) * scale).rounded(), height: (CGFloat(image.height) * scale).rounded())
    }
}
