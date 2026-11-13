import SwiftUI

extension EnvironmentValues {
    @Entry var gradesLocked = false
    @Entry var unlockGrades: @MainActor () -> Void = {}
}

enum SensitiveStyle {
    case inline
    case control
    case block
}

private struct Sensitive: ViewModifier {
    let style: SensitiveStyle?
    @Environment(\.gradesLocked) private var locked
    @Environment(\.unlockGrades) private var unlock

    func body(content: Content) -> some View {
        if !locked || style == nil {
            content
        } else {
            // redact할 수 있는 것은 글뿐이고, blur는 차트의 모양이나 슬라이더의 위치를 알아볼 수 있게 남긴다. 그래서
            // 글이 아닌 것은 크기만 지키고 아예 그리지 않는다.
            switch style {
            case .inline, .control:
                Group {
                    if style == .control {
                        content.hidden()
                            .overlay { Capsule().fill(Theme.Palette.textTertiary.opacity(0.18)).frame(height: 6) }
                    } else {
                        content.redacted(reason: .placeholder)
                    }
                }
                .allowsHitTesting(false)
                .overlay { Color.clear.contentShape(.rect).onTapGesture { unlock() } }
                .pointingHand()
                .help(Text(.designUnlockHelp))
                .accessibilityElement()
                .accessibilityLabel(Text(.designLockedGrade))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { unlock() }
            case .block, nil:
                content.hidden()
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.card)
                            .fill(Theme.Palette.card)
                            .strokeBorder(Theme.Palette.lineSoft)
                    }
                    .accessibilityHidden(true)
                    .overlay {
                        Button {
                            unlock()
                        } label: {
                            Label(.commonUnlockGrades, systemImage: "lock.fill")
                        }
                        .buttonStyle(.pointing(.glass))
                    }
            }
        }
    }
}

extension View {
    func sensitive(_ style: SensitiveStyle? = .inline) -> some View { modifier(Sensitive(style: style)) }
}
