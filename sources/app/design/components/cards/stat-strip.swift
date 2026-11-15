import FolioDomain
import SwiftUI

struct StatStrip: View {
    struct Item: Identifiable {
        var id: String { title }
        let title: String
        let value: String
        var detail: String?
        var tone: Tone = .plain
        var sensitive = false
        var action: (() -> Void)?
    }

    let items: [Item]

    static let itemRoom: CGFloat = 128

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(items).frame(idealWidth: CGFloat(items.count) * Self.itemRoom)
            VStack(spacing: 0) {
                ForEach(Array(stride(from: 0, to: items.count, by: 2)), id: \.self) { start in
                    if start > 0 { Theme.Palette.lineSoft.frame(height: 1) }
                    row(Array(items[start..<min(start + 2, items.count)]))
                }
            }
        }
        .surface(Theme.Palette.card, in: .rect(cornerRadius: Theme.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.Palette.lineSoft))
    }

    func row(_ items: [Item]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Theme.Palette.lineSoft.frame(width: 1) }
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Caption(item.title)
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Text(item.value).font(Theme.Typeface.figureSmall).foregroundStyle(item.tone.foreground).lineLimit(1).rolling(
                            item.value)
                        if let detail = item.detail {
                            Text(detail).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary).lineLimit(1)
                        }
                    }
                    .sensitive(item.sensitive ? .inline : nil)
                }
                .padding(Theme.Inset.stat)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .opens(item.action)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
