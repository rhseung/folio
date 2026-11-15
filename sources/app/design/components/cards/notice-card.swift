import FolioDomain
import SwiftUI

struct NoticeCard<Trailing: View, Rows: View>: View {
    let title: String
    var detail: String?
    var systemImage = "exclamationmark.bubble.fill"
    var informs = false
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var rows: Rows

    var body: some View {
        Card {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Space.m) {
                    words(detailIdeal: 0)
                    Spacer(minLength: Theme.Space.s)
                    action
                }
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    words(detailIdeal: nil)
                    action.padding(.leading, Theme.Space.m + Theme.Size.tile)
                }
            }
            .padding(Theme.Inset.row)
            .frame(maxWidth: .infinity, minHeight: Theme.Size.rowHeight, alignment: .leading)
            .background(informs ? Theme.Palette.infoFill : Theme.Palette.warningBanner, in: .rect(cornerRadius: Theme.Radius.card))
            rows
        }
    }
}

extension NoticeCard {
    func words(detailIdeal: CGFloat?) -> some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: systemImage).foregroundStyle(informs ? Theme.Palette.info : Theme.Palette.warning).font(
                Theme.Typeface.bodyStrong
            )
            .frame(width: Theme.Size.tile)
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(title).font(Theme.Typeface.bodyStrong).lineLimit(1)
                if let detail {
                    Text(detail).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(idealWidth: detailIdeal, maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    var action: some View { trailing.lineLimit(1).fixedSize() }
}

extension NoticeCard where Rows == EmptyView {
    init(title: String, detail: String? = nil, systemImage: String = "exclamationmark.bubble.fill", @ViewBuilder trailing: () -> Trailing) {
        self.init(title: title, detail: detail, systemImage: systemImage, trailing: trailing, rows: { EmptyView() })
    }
}
