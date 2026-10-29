import SwiftUI

extension EnvironmentValues {
    /// Set at the root from the workspace's lock, so design components can hide grades without knowing the workspace.
    @Entry var gradesLocked = false
    @Entry var unlockGrades: @MainActor () -> Void = {}
}

enum SensitiveStyle {
    /// A figure: placeholder bars, and a press on them unlocks.
    case inline
    /// A control such as the grade track: drawn as an empty bar.
    case control
    /// A whole card: drawn empty, with an unlock button over it.
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
            // Only text can be redacted, and a blur keeps a chart's shape or a slider's position readable, so anything
            // beyond text keeps its size and is not drawn at all.
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
                    .help("눌러서 성적 잠금 해제")
                    .accessibilityElement()
                    .accessibilityLabel("잠긴 성적")
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
                        Button { unlock() } label: { Label("성적 잠금 해제", systemImage: "lock.fill") }
                            .buttonStyle(.pointing(.glass))
                    }
            }
        }
    }
}

extension View {
    /// Hides grade content while grades are locked; nil leaves it shown.
    func sensitive(_ style: SensitiveStyle? = .inline) -> some View { modifier(Sensitive(style: style)) }
}
