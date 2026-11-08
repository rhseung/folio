import FolioDomain
import SwiftUI

/// The pointing hand over anything clickable on Mac. Wraps the base style, so `.plain` or `.borderless` keep their look;
/// set once at the root for unstyled buttons and around every explicit `.buttonStyle`, which would otherwise replace it.
struct PointingButtonStyle<Base: PrimitiveButtonStyle>: PrimitiveButtonStyle {
    let base: Base
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button(configuration).buttonStyle(base)
            #if os(macOS)
            .pointerStyle(isEnabled ? .link : nil)
            #endif
    }
}

extension PrimitiveButtonStyle {
    static func pointing<Base: PrimitiveButtonStyle>(_ base: Base) -> Self where Self == PointingButtonStyle<Base> { .init(base: base) }
}

/// A screen's one main action: `.borderedProminent` filled with the course's colour inside a course, the system accent
/// outside one. Set here, not by the tint around it: a course tints its pages with its ink, pale in dark, and a sheet
/// doesn't take the tint of the view it opens from, only the `accent` it is handed.
struct ProminentButtonStyle: PrimitiveButtonStyle {
    @Environment(\.accent) private var accent

    func makeBody(configuration: Configuration) -> some View {
        // `.gray` is the accent where no course is in view.
        Button(configuration).buttonStyle(.pointing(.borderedProminent))
            .tint(accent == .gray ? Color.accentColor : accent.fill)
    }
}

extension PrimitiveButtonStyle where Self == ProminentButtonStyle {
    static var prominent: ProminentButtonStyle { .init() }
}

extension View {
    /// The pointing hand for menus: a custom button style on a `.button`-style menu turns it back into a pop-up.
    func pointingHand() -> some View {
        #if os(macOS)
        pointerStyle(.link)
        #else
        self
        #endif
    }

    /// Clicking anywhere in the container runs `action`; buttons inside it keep their own clicks.
    func opens(_ action: (() -> Void)?) -> some View {
        #if os(macOS)
        contentShape(.rect).onTapGesture { action?() }.pointerStyle(action == nil ? nil : .link)
        #else
        contentShape(.rect).onTapGesture { action?() }
        #endif
    }
}

extension EnvironmentValues {
    /// The item of a list page the window's link names (an exam, a session): `Page` scrolls to it and its row is marked.
    @Entry var linkFocus: UUID?
}

extension View {
    /// A row a link can name. While the window's link names it, it is marked as chosen, and edged in the course color
    /// for a moment when the link arrives, so the eye finds it after the scroll.
    func linkTarget(_ id: UUID) -> some View { modifier(LinkTarget(id: id)) }
}

private struct LinkTarget: ViewModifier {
    let id: UUID
    @Environment(\.linkFocus) private var focus
    @Environment(\.accent) private var accent
    @State private var lit = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if focus == id {
                    RoundedRectangle(cornerRadius: Theme.Radius.control)
                        .fill(accent.tint)
                        .strokeBorder(accent.color.opacity(lit ? 1 : 0), lineWidth: 2)
                        .allowsHitTesting(false)
                }
            }
            .id(id)
            .task(id: focus) {
                guard focus == id else { return lit = false }
                lit = true
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation(.easeOut(duration: 0.8)) { lit = false }
            }
    }
}

extension View {
    /// Takes files dropped from outside (Finder, Files, another app), outlined in the accent while they hover.
    func fileDrop(_ perform: @escaping ([URL]) -> Void) -> some View { modifier(FileDrop(perform: perform)) }

    /// Lets the file be dragged out, for example into a browser's upload field.
    func fileDrag(_ url: URL) -> some View {
        // shortcut: an iCloud placeholder that isn't downloaded yet drags as nothing; download first if that bites.
        onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
    }
}

private struct FileDrop: ViewModifier {
    @Environment(\.accent) private var accent
    let perform: ([URL]) -> Void
    @State private var targeted = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if targeted {
                    RoundedRectangle(cornerRadius: Theme.Radius.control)
                        .strokeBorder(accent.color, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .allowsHitTesting(false)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                let files = urls.filter(\.isFileURL)
                if !files.isEmpty { perform(files) }
                return !files.isEmpty
            } isTargeted: { targeted = $0 }
    }
}
