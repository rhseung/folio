import FolioDomain
import SwiftUI

struct Chip: View {
    @Environment(\.accent) private var accent
    let text: String
    var tone: Tone = .plain
    var solid = false

    init(_ text: String, tone: Tone = .plain, solid: Bool = false) {
        self.text = text
        self.tone = tone
        self.solid = solid
    }

    var body: some View {
        Text(text)
            .font(Theme.Typeface.caption.weight(tone == .plain && !solid ? .regular : .semibold))
            // 채운 칩에서는 `onFill`이 아니라 카드 색을 쓴다. 다크 모드의 진한 톤은 밝아서 흰 글자의 대비가 3:1보다
            // 낮았다.
            .foregroundStyle(
                solid ? Theme.Palette.card : tone == .accent ? accent.ink : tone == .plain ? Theme.Palette.textSecondary : tone.foreground
            )
            .lineLimit(1)
            .fixedSize()
            .padding(Theme.Inset.tag)
            .background(solid ? tone.foreground : tone == .accent ? accent.tint : tone.fill, in: .capsule)
    }
}
