#if os(macOS)
import AppKit
import SwiftUI

/// The window's top row at `Theme.Size.toolbarRow` (48pt): 32pt capsules with 8pt above and below (#62).
///
/// Drawn here rather than by an AppKit toolbar. Its styles give a 40pt (`unifiedCompact`) or a 52pt (`unified`) row
/// and nothing between, and a compact toolbar padded out to 48pt came apart each time AppKit laid the title bar out
/// again (the zoom button alone back at the compact row's middle). So the window hides its title bar (`.hiddenTitleBar`
/// in `FolioApp`) and this row is the top of its content: its height and layout are ours, its empty parts drag the
/// window (`TitleDrag`), and the window's buttons are moved onto its middle (`TrafficLights`).
struct TitleRow<Leading: View, Trailing: View>: View {
    /// From the window's leading edge to the first item.
    let lead: CGFloat
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 0) {
            leading
            Spacer(minLength: 0)
            trailing
        }
        .padding(.leading, lead)
        .padding(.trailing, TitleRowEdges.trailing)
        .frame(height: Theme.Size.toolbarRow)
        // Behind the items, so only the row's empty parts reach it: between the capsules, above and below them.
        .background { TitleDrag() }
    }
}

/// Where the title row's items begin and end across the window, which `ToolbarRow` fits the tabs between.
enum TitleRowEdges {
    /// The close button's center, as far from the window's left edge as from its top (the row's middle). AppKit
    /// leaves it 16pt from the side in a window without a title bar, nearer the side than the top, which looked
    /// lopsided and stood left of the sidebar's icons. The other two buttons follow at AppKit's spacing.
    static let lights = Theme.Size.toolbarRow / 2

    /// From the window's leading edge to the first item: past the window's buttons, at the gap the compact toolbar
    /// left after them (84pt with the buttons where AppKit puts them), plus the 8pt they move right (`lights`). In
    /// full screen the buttons are in the menu bar's reveal, so the row starts as far in as the content panel.
    static func lead(fullScreen: Bool) -> CGFloat { fullScreen ? Theme.Size.panelInset : 92 }

    /// The last capsule ends as far from the window's right edge as the capsules sit below its top (8pt), as the
    /// window's buttons do on the left (`lights`). Ended at the content panel's edge (`panelInset`, 4pt), the
    /// capsules crowded the window's corner, half as far from the side as from the top.
    static let trailing = (Theme.Size.toolbarRow - Theme.Size.toolbarButton) / 2
}

/// The title row's empty space: dragging it moves the window and a double-click does what the system's setting says,
/// as on a title bar. An AppKit view, since SwiftUI's `WindowDragGesture` has no double-click.
struct TitleDrag: NSViewRepresentable {
    func makeNSView(context: Context) -> Band { Band() }
    func updateNSView(_ view: Band, context: Context) {}

    final class Band: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            if event.clickCount == 2 {
                // The same setting the title bar follows (Desktop & Dock, "Double-click a window's title bar to").
                switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
                case "Minimize": window.performMiniaturize(nil)
                case "None": break
                default: window.performZoom(nil)
                }
            } else {
                window.performDrag(with: event)
            }
        }
    }
}

/// Moves the window's close, minimize and zoom buttons so their center is `center` from the window's top and the close
/// button's is `center` from its left edge, and tells whether the window is going into full screen, where the buttons
/// leave the row.
///
/// AppKit lays the buttons out again whenever the title bar changes (the window becoming key, its title changing with
/// each tab, resize, leaving full screen), each time back on the title bar's own middle. It moves close, then minimize,
/// then zoom, and a button set back while that pass runs reads as already in place, so the last one moved (zoom) was
/// left behind. So the buttons are set only after the pass: every frame change AppKit makes, and every change of the
/// window, asks for one placing on the next turn of the run loop, before the window is drawn. The target is in window
/// coordinates, so placing again is a no-op. Only public API: `standardWindowButton` and frames. In full screen the
/// buttons live in the menu-bar reveal, another window, and are left alone.
struct TrafficLights: NSViewRepresentable {
    let center: CGFloat
    let fullScreen: (Bool) -> Void

    func makeNSView(context: Context) -> Probe { Probe(center: center, fullScreen: fullScreen) }
    func updateNSView(_ view: Probe, context: Context) {
        view.center = center
        view.fullScreen = fullScreen
        view.place()
    }

    final class Probe: NSView {
        var center: CGFloat
        var fullScreen: (Bool) -> Void
        private var windowObservers: [NSObjectProtocol] = []
        private var frameObservers: [NSObjectProtocol] = []
        /// The buttons whose frames are watched.
        private var watched: [ObjectIdentifier] = []
        /// Each watched button's middle from the close button's, across the window, as AppKit spaced them.
        private var spacing: [CGFloat] = []

        init(center: CGFloat, fullScreen: @escaping (Bool) -> Void) {
            self.center = center
            self.fullScreen = fullScreen
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            for observer in windowObservers + frameObservers { NotificationCenter.default.removeObserver(observer) }
            windowObservers = []
            frameObservers = []
            watched = []
            guard let window else { return }
            let center = NotificationCenter.default
            let changes: [Notification.Name] = [
                NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification, NSWindow.didBecomeKeyNotification,
                NSWindow.didResignKeyNotification, NSWindow.didBecomeMainNotification, NSWindow.didResignMainNotification,
                NSWindow.didExitFullScreenNotification, NSWindow.didChangeBackingPropertiesNotification,
                NSWindow.didChangeScreenNotification, NSWindow.didDeminiaturizeNotification,
            ]
            windowObservers = changes.map { name in
                center.addObserver(forName: name, object: window, queue: nil) { [weak self] _ in
                    MainActor.assumeIsolated { self?.placeNowAndNextTurn() }
                }
            }
            let going: [(Notification.Name, Bool)] = [(NSWindow.willEnterFullScreenNotification, true), (NSWindow.willExitFullScreenNotification, false)]
            windowObservers += going.map { name, full in
                center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.fullScreen(full) }
                }
            }
            let full = window.styleMask.contains(.fullScreen)
            // Joining the window happens while SwiftUI updates its views, which mustn't change what they read.
            Task { @MainActor [weak self] in self?.fullScreen(full) }
            placeNowAndNextTurn()
        }

        static let kinds: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]

        private var placingNextTurn = false

        private func placeNowAndNextTurn() {
            place()
            placeNextTurn()
        }

        private func placeNextTurn() {
            guard !placingNextTurn else { return }
            placingNextTurn = true
            Task { @MainActor [weak self] in
                self?.placingNextTurn = false
                self?.place()
            }
        }

        func place() {
            guard let window, !window.styleMask.contains(.fullScreen) else { return }
            let buttons = Self.kinds.compactMap { window.standardWindowButton($0) }.filter { $0.window === window }
            watch(buttons)
            for (button, offset) in zip(buttons, spacing) {
                guard let host = button.superview else { continue }
                let inWindow = host.convert(button.frame, to: nil)
                var target = inWindow
                target.origin.x = center + offset - inWindow.width / 2
                target.origin.y = window.frame.height - center - inWindow.height / 2
                let frame = host.convert(target, from: nil)
                // Rounded to the pixel, or the frame drifts by a fraction and the watch sets it forever.
                let origin = host.backingAlignedRect(frame, options: .alignAllEdgesNearest).origin
                if abs(button.frame.origin.x - origin.x) > 0.25 || abs(button.frame.origin.y - origin.y) > 0.25 {
                    button.setFrameOrigin(origin)
                }
            }
        }

        /// Again whenever AppKit hands out other buttons, so a title bar built anew is still watched.
        private func watch(_ buttons: [NSButton]) {
            let ids = buttons.map(ObjectIdentifier.init)
            guard ids != watched else { return }
            for observer in frameObservers { NotificationCenter.default.removeObserver(observer) }
            watched = ids
            // Read once, from buttons not yet moved: read at each placing, a button AppKit had just put back while the
            // others stood moved would bake that gap into the spacing.
            let middles = buttons.map { $0.convert($0.bounds, to: nil).midX }
            spacing = middles.map { $0 - (middles.first ?? 0) }
            frameObservers = buttons.map { button in
                button.postsFrameChangedNotifications = true
                // Not placed here, inside AppKit's pass, where the move doesn't hold (see above).
                return NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: button, queue: nil) { [weak self] _ in
                    MainActor.assumeIsolated { self?.placeNextTurn() }
                }
            }
        }
    }
}
#endif
