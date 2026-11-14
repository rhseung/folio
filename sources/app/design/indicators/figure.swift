import FolioDomain
import SwiftUI

struct Figure: View {
    let title: String
    let value: String
    var tint: Color = Theme.Palette.text
    var font: Font = Theme.Typeface.figure

    init(_ title: String, _ value: String, tint: Color = Theme.Palette.text, font: Font = Theme.Typeface.figure) {
        self.title = title
        self.value = value
        self.tint = tint
        self.font = font
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Caption(title)
            Text(value).font(font).foregroundStyle(tint).rolling(value).lineLimit(1).minimumScaleFactor(0.6)
        }
    }
}
