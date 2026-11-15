import FolioDomain
import SwiftUI

struct Chip: View {
    @Environment(\.accent) private var accent
    let text: String
    var tone: Tone = .plain
    var solid = false
    var color: Color?

    init(_ text: String, tone: Tone = .plain, solid: Bool = false) {
        self.text = text
        self.tone = tone
        self.solid = solid
    }

    // 상태의 뜻이 아니라 값으로 색이 정해지는 칩(시험까지 남은 날)이다. 글자는 그 색, 바탕은 그 색을 옅게 깐다.
    init(_ text: String, color: Color) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(Theme.Typeface.caption.weight(tone == .plain && !solid && color == nil ? .regular : .semibold))
            .monospacedDigit()
            .foregroundStyle(ink)
            .lineLimit(1)
            .fixedSize()
            .chip(.small, fill: fill)
    }

    // 채운 칩에서는 `onFill`이 아니라 카드 색을 쓴다. 다크 모드의 진한 톤은 밝아서 흰 글자의 대비가 3:1보다 낮았다.
    var ink: Color {
        if let color { return color }
        if solid { return Theme.Palette.card }
        return switch tone {
        case .accent: accent.ink
        case .plain: Theme.Palette.textSecondary
        default: tone.foreground
        }
    }

    var fill: Color {
        if let color { return color.opacity(Theme.Opacity.tint) }
        if solid { return tone.foreground }
        return tone == .accent ? accent.tint : tone.fill
    }
}
