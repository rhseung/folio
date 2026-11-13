import SwiftUI

/// Color comes from `.tint(_:)`, not `.foregroundStyle(_:)`, which the style's own foreground would cover.
struct GhostButtonStyle: ButtonStyle {
    /// For a `Label` shown as its icon alone; a `.labelStyle(.iconOnly)` outside would lose to the style's own.
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
        // Also here, not only in `GhostLabelStyle`: a button labelled with plain text never reaches the label style (#402).
        .lineLimit(1)
        .foregroundStyle(tint)
        // Drawn outside the label's frame, so the words stay level with the text beside them.
        .background {
            Capsule().fill(tint).opacity(configuration.isPressed ? 0.2 : hovering && isEnabled ? 0.12 : 0)
                .padding(.horizontal, -6).padding(.vertical, -4)
        }
        // An icon alone is a 16pt target, too small for a finger (the clear ✕, the ⋯ menu).
        .contentShape(TouchTarget(side: iconOnly ? Theme.Size.touchTarget : 0))
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { hovering = $0 }
        #if os(macOS)
        .pointerStyle(isEnabled ? .link : nil)
        #endif
    }
}

/// The system Label leaves a gap wider than the one between neighboring buttons, so an icon read as the button before it.
struct GhostLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Theme.Space.xs) {
            configuration.icon.imageScale(.small).fontWeight(.semibold)
            configuration.title.lineLimit(1)
        }
    }
}

/// The system's own toolbar buttons sit in glass capsules that crowded the compact row, and without the capsule they
/// are spaced far apart.
struct ToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ToolbarButton(configuration: configuration)
    }
}

private struct ToolbarButton: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        // A label that sets its own style inside (the running timer's time) keeps it; the rest show the icon.
        configuration.label.labelStyle(.iconOnly)
            .font(Theme.Glyph.toolbar)
            // A label of text (the running timer's time) keeps its width and one line, as every bar item does.
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(Theme.Palette.chromeIcon)
            // A fixed square, not padding and a minimum: the glyph's own width left it off the hover circle's center.
            .frame(minWidth: Theme.Size.toolbarButton, minHeight: Theme.Size.toolbarButton)
            .background {
                // Inset so the hover stays inside a toolbar group's capsule, which is the buttons' own height.
                Capsule().fill(Theme.Palette.text).opacity(configuration.isPressed ? Theme.Opacity.pressed : hovering && isEnabled ? Theme.Opacity.hover : 0)
                    .padding(Theme.Space.xxs)
            }
            .contentShape(.capsule)
            .opacity(isEnabled ? 1 : Theme.Opacity.disabled)
            .onHover { hovering = $0 }
    }
}

extension ButtonStyle where Self == ToolbarButtonStyle {
    static var toolbar: ToolbarButtonStyle { .init() }
}

extension ButtonStyle where Self == GhostButtonStyle {
    static var ghost: GhostButtonStyle { .init() }
    static var ghostIcon: GhostButtonStyle { .init(iconOnly: true) }
}
