import FolioDomain
import SwiftUI

struct PageHeader<Chips: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var chips: Chips

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.tight) { chips }
            Text(title).font(Theme.Typeface.pageTitle).lineLimit(1)
            if let subtitle { Text(subtitle).foregroundStyle(Theme.Palette.textTertiary) }
        }
    }
}

extension PageHeader where Chips == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}
