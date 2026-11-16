import FolioDomain
import SwiftUI

struct KeyCap: View {
    let key: String
    init(_ key: String) { self.key = key }
    var body: some View {
        Text(key).font(Theme.Typeface.label).monospaced()
            .foregroundStyle(Theme.Palette.textSecondary)
            .lineLimit(1).fixedSize()
            .padding(.horizontal, Theme.Space.tight).padding(.vertical, Theme.Space.xxs)
            .background(Theme.Palette.fill, in: .rect(cornerRadius: Theme.Radius.small))
    }
}
