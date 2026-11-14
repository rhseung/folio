import FolioDomain
import SwiftUI

struct CardRow<Content: View>: View {
    var last = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Space.m) { content }
                .padding(Theme.Inset.row)
                .frame(maxWidth: .infinity, minHeight: Theme.Size.rowHeight, alignment: .leading)
            if !last { Theme.Palette.lineSoft.frame(height: 1).padding(.leading, Theme.Space.l) }
        }
    }
}
