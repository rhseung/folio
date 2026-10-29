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
