import FolioDomain
import SwiftUI

struct SectionStrip: View {
    let sections: [PageRangeField.Section]
    let pages: Int
    let range: ClosedRange<Int>?
    var width: CGFloat = 72

    @Environment(\.accent) private var accent

    var body: some View {
        Canvas { context, size in
            let n = CGFloat(max(pages, 1))
            func x(_ edge: Int) -> CGFloat { CGFloat(edge) / n * size.width }
            for (i, s) in sections.enumerated() where s.pages.lowerBound <= pages {
                let lo = x(s.pages.lowerBound - 1) + (i == 0 ? 0 : 0.5)
                let hi = x(min(s.pages.upperBound, pages)) - (i == sections.count - 1 ? 0 : 0.5)
                let rect = CGRect(x: lo, y: 0, width: max(hi - lo, 1), height: size.height)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: Theme.Radius.mark),
                    with: .color(s.title.isEmpty ? Theme.Palette.fill : Theme.Palette.text.opacity(Theme.Opacity.toneEdge)))
            }
            if let range {
                let lo = x(range.lowerBound - 1), hi = x(min(range.upperBound, pages))
                context.fill(
                    Path(roundedRect: CGRect(x: lo, y: 0, width: max(hi - lo, 2), height: size.height), cornerRadius: Theme.Radius.mark),
                    with: .color(accent.color))
            }
        }
        .frame(width: width, height: Self.height)
        .accessibilityHidden(true)
    }

    static let height: CGFloat = 6
}
