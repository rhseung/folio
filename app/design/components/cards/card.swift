import FolioDomain
import SwiftUI

struct Card<Content: View>: View {
    var padding: CGFloat = 0
    var clipped = false
    @ViewBuilder var content: Content

    var body: some View {
        let rows = VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
        // 요청할 때만 자른다. 모든 카드를 자르면 행이 가장자리 밖에 그리는 것이 잘렸다.
        Group { if clipped { rows.clipShape(.rect(cornerRadius: Theme.Radius.card)) } else { rows } }
            .surface(Theme.Palette.card, in: .rect(cornerRadius: Theme.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.Palette.lineSoft))
    }
}
