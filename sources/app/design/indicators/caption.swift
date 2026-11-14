import FolioDomain
import SwiftUI

struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(Theme.Typeface.label).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
    }
}
