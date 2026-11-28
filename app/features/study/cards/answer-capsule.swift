import FolioDomain
import SwiftUI

// 카드에 답하는 단추다. 노트 옆 칸에 쌓인 카드마다 놓이므로 작은 캡슐로 두고, 누르는 자리만 터치 표적만큼 넓힌다.
struct AnswerCapsule: View {
    enum Look {
        case plain, yes, no
    }

    let title: String
    var systemImage: String?
    var look = Look.plain
    var key: ShortcutID?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.xs) {
                if let systemImage { Image(systemName: systemImage).imageScale(.small).accessibilityHidden(true) }
                Text(title)
            }
            .font(Theme.Typeface.bodyStrong)
            .foregroundStyle(ink)
            .lineLimit(1)
            .padding(.horizontal, Theme.Space.m)
            .frame(minWidth: Theme.Size.touchTarget, minHeight: Theme.Size.answerCapsule)
            .background(fill, in: .capsule)
            .contentShape(TouchTarget())
        }
        .buttonStyle(.pointing(.plain))
        .shortcut(key)
    }

    var ink: Color {
        switch look {
        case .plain: Theme.Palette.text
        case .yes: Tone.success.foreground
        case .no: Tone.danger.foreground
        }
    }

    var fill: Color {
        switch look {
        case .plain: Theme.Palette.fill
        case .yes: Tone.success.fill
        case .no: Tone.danger.fill
        }
    }
}
