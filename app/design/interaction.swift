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

/// The course's colour is set here, not by the tint around it: a course tints its pages with its ink, pale in dark,
/// and a sheet doesn't take the tint of the view it opens from, only the `accent` it is handed.
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

/// A small control's hit area grown to `side` on each side around what is drawn, without moving it or its neighbours. Only
/// on touch: a pointer aims finer, and on the Mac the wider area would take clicks meant for the views beside it.
struct TouchTarget: Shape {
    var side: CGFloat = Theme.Size.touchTarget

    func path(in rect: CGRect) -> Path {
        #if os(macOS)
        Path(rect)
        #else
        Path(rect.insetBy(dx: min(0, (rect.width - side) / 2), dy: min(0, (rect.height - side) / 2)))
        #endif
    }
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
    func fileDrop(_ perform: @escaping ([URL]) -> Void) -> some View { modifier(FileDrop(perform: perform)) }

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
            } isTargeted: {
                targeted = $0
            }
    }
}

/// What a press on a row of a list that picks several rows means: the row alone, the rows from the last pick to it,
/// or that row added or taken away.
enum PickPress { case only, range, toggle }

extension View {
    /// A press on a row of a list that picks several. On a Mac ⇧ widens and ⌘ adds or takes away. A touch screen has
    /// no keys to hold: a long press starts picking (`hold`), and while `picking` a tap means `touch`. A hardware
    /// keyboard's ⇧ and ⌘ still work on an iPad. The transcript's lines and the add sheet's rows both pick this way.
    func picks(picking: Bool, touch: PickPress, hold: @escaping () -> Void, _ press: @escaping (PickPress) -> Void) -> some View {
        modifier(Picks(picking: picking, touch: touch, hold: hold, press: press))
    }
}

private struct Picks: ViewModifier {
    let picking: Bool
    let touch: PickPress
    let hold: () -> Void
    let press: (PickPress) -> Void

    #if os(macOS)
    func body(content: Content) -> some View {
        // The click's own flags: the keyboard's live state (`NSEvent.modifierFlags`) misses a key the click carries
        // but no key holds, as from Accessibility or a scripted click.
        content.contentShape(.rect).onTapGesture {
            let flags = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
            press(flags.contains(.shift) ? .range : flags.contains(.command) ? .toggle : .only)
        }
    }
    #else
    @State private var keys = HeldKeys()
    @State private var holds = 0

    func body(content: Content) -> some View {
        content.contentShape(.rect)
            // SwiftUI's tap: UIKit's, which carries the keys, would also fire beside the buttons and menus in the row.
            .onTapGesture {
                let flags = keys.flags
                press(flags.contains(.shift) ? .range : flags.contains(.command) ? .toggle : picking ? touch : .only)
            }
            .onLongPressGesture {
                holds += 1
                hold()
            }
            .gesture(KeyProbe(keys: keys))
            .sensoryFeedback(.selection, trigger: holds)
    }
    #endif
}

#if os(iOS)
/// The hardware keyboard's keys held as the last touch began. SwiftUI's tap carries no modifier keys and its
/// `onModifierKeysChanged` is Mac-only, so a recognizer reads them off the touch's event.
@MainActor private final class HeldKeys {
    var flags: UIKeyModifierFlags = []
}

private struct KeyProbe: UIGestureRecognizerRepresentable {
    let keys: HeldKeys

    func makeUIGestureRecognizer(context: Context) -> Probe { Probe(keys: keys) }

    /// Reads the keys and fails at once, so it never holds back or cancels the touch for anything else.
    final class Probe: UIGestureRecognizer {
        let keys: HeldKeys

        init(keys: HeldKeys) {
            self.keys = keys
            super.init(target: nil, action: nil)
            cancelsTouchesInView = false
            delaysTouchesEnded = false
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            keys.flags = event.modifierFlags
            state = .failed
        }
    }
}
#endif

struct PickingLine: View {
    let text: String
    let done: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Text(text).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary)
            Spacer(minLength: Theme.Space.s)
            Button(.commonDone, action: done).buttonStyle(.ghost)
        }
    }
}
