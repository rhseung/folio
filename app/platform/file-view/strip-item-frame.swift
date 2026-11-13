import SwiftUI

/// The pieces of a section's tint meet square and round only at its header's top and under its last page, so an
/// unfolded section reads as one surface from its header down.
/// Every page sits in the column's middle, so crossing into or out of a section moves no thumbnail sideways.
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
            // Short of the gap under the last page, or under a folded header, so the next item stands apart.
            .padding(.bottom, last ? Theme.Space.xs : 0)
        }
    }
}
