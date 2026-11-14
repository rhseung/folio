import SwiftUI

// `.foregroundStyle(_:)`로 준 색은 스타일 자신의 전경색에 덮이므로, 색은 `.tint(_:)`로 받는다.
struct GhostButtonStyle: ButtonStyle {
    // 바깥에서 `.labelStyle(.iconOnly)`를 주면 스타일 자신의 label style에 밀리므로 이 값으로 받는다.
    var iconOnly = false

    func makeBody(configuration: Configuration) -> some View {
        GhostButton(configuration: configuration, iconOnly: iconOnly)
    }
}

private struct GhostButton: View {
    let configuration: ButtonStyleConfiguration
    let iconOnly: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        let tint = configuration.role == .destructive ? AnyShapeStyle(Theme.Palette.danger) : AnyShapeStyle(.tint)
        Group {
            if iconOnly { configuration.label.labelStyle(.iconOnly) } else { configuration.label.labelStyle(GhostLabelStyle()) }
        }
        // `GhostLabelStyle`에만 두지 않고 여기에도 둔다. 일반 글자로 이름을 붙인 버튼은 label style을 거치지 않기
        // 때문이다.
        .lineLimit(1)
        .foregroundStyle(tint)
        .background {
            Capsule().fill(tint).opacity(configuration.isPressed ? 0.2 : hovering && isEnabled ? 0.12 : 0)
                .padding(.horizontal, -6).padding(.vertical, -4)
        }
        .contentShape(TouchTarget(side: iconOnly ? Theme.Size.touchTarget : 0))
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { hovering = $0 }
        #if os(macOS)
        .pointerStyle(isEnabled ? .link : nil)
        #endif
    }
}
