import SwiftUI

struct StripItemFrame<Content: View>: View {
    let item: StripItem
    @ViewBuilder var content: Content
    @Environment(\.accent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .background { tint }
            .padding(.horizontal, Theme.Space.s)
    }

    @ViewBuilder private var tint: some View {
        if case .tinted(let last) = item.mark {
            let first = item.lead != nil
            let r = Theme.Radius.strip
            UnevenRoundedRectangle(
                topLeadingRadius: first ? r : 0, bottomLeadingRadius: last ? r : 0,
                bottomTrailingRadius: last ? r : 0, topTrailingRadius: first ? r : 0
            )
            .fill(accent.tint)
            .padding(.bottom, last ? Theme.Space.xs : 0)
        }
    }
}
