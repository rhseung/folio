#if os(macOS)
import AppKit
import SwiftUI

/// The window's top row at `Theme.Size.toolbarRow` (48pt): 32pt capsules with 8pt above and below (#62).
///
/// AppKit's toolbar styles give 40pt (`unifiedCompact`) or 52pt (`unified`) and nothing between: taller items don't
/// grow the compact row. So the window keeps the compact toolbar, which still does what a titlebar does (drag,
/// double-click, full screen, the items' own layout), and the row is made up to 48pt around it:
/// - the items are padded at the top by the difference (`extra`), which moves their capsules down by half of it into
///   the band below the toolbar, centered on the 48pt row;
/// - the content starts the difference lower, and that band drags and zooms the window like the toolbar (`TitleDrag`);
/// - the window's buttons are moved down by half of it onto the capsules' center line (`TrafficLights`).
enum TitleRow {
    /// What the row adds under the toolbar, from the toolbar's height as the window reports it (its top safe area).
    /// Nothing for a toolbar outside the compact row's range, so a toolbar AppKit ever sizes otherwise (or none in a
    /// full-screen window that hid it) keeps its own row rather than being padded off the mark.
    static func extra(toolbar: CGFloat) -> CGFloat {
        (28...Theme.Size.toolbarRow).contains(toolbar) ? Theme.Size.toolbarRow - toolbar : 0
    }
}

/// The band the row adds under the toolbar: dragging it moves the window and a double-click does what the system's
/// setting says, as on the toolbar above it. An AppKit view, since SwiftUI's `WindowDragGesture` has no double-click.
struct TitleDrag: NSViewRepresentable {
    func makeNSView(context: Context) -> Band { Band() }
    func updateNSView(_ view: Band, context: Context) {}

    final class Band: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            if event.clickCount == 2 {
                // The same setting the titlebar follows (Desktop & Dock, "Double-click a window's title bar to").
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

/// Moves the window's close, minimize and zoom buttons so their center is `center` from the window's top.
///
/// AppKit lays the buttons out again whenever the titlebar changes (resize, toolbar, key state), each time back on the
/// compact row's center. So each button's frame is watched and set again whenever AppKit moves it; the target is in
/// window coordinates, so setting it again is a no-op. Only public API: `standardWindowButton` and frames. In full
/// screen the buttons live in the menu-bar reveal, another window, and are left alone.
struct TrafficLights: NSViewRepresentable {
    let center: CGFloat

    func makeNSView(context: Context) -> Probe { Probe(center: center) }
    func updateNSView(_ view: Probe, context: Context) {
        view.center = center
        view.place()
    }

    final class Probe: NSView {
        var center: CGFloat
        private var observers: [NSObjectProtocol] = []

        init(center: CGFloat) {
            self.center = center
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            observers = []
            guard let window else { return }
            let buttons = Self.kinds.compactMap { window.standardWindowButton($0) }
            for button in buttons { button.postsFrameChangedNotifications = true }
            let watched: [(Notification.Name, AnyObject)] = buttons.map { (NSView.frameDidChangeNotification, $0) }
                + [NSWindow.didResizeNotification, NSWindow.didExitFullScreenNotification, NSWindow.didBecomeKeyNotification,
                   NSWindow.didResignKeyNotification].map { ($0, window) }
            observers = watched.map { name, object in
                NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.place() }
                }
            }
            place()
        }

        static let kinds: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]

        func place() {
            guard let window, !window.styleMask.contains(.fullScreen) else { return }
            for kind in Self.kinds {
                guard let button = window.standardWindowButton(kind), button.window === window, let host = button.superview else { continue }
                let inWindow = host.convert(button.frame, to: nil)
                var target = inWindow
                target.origin.y = window.frame.height - center - inWindow.height / 2
                let frame = host.convert(target, from: nil)
                // Rounded to the pixel, or the frame drifts by a fraction and the watch sets it forever.
                let origin = host.backingAlignedRect(frame, options: .alignAllEdgesNearest).origin
                if abs(button.frame.origin.y - origin.y) > 0.25 { button.setFrameOrigin(NSPoint(x: button.frame.origin.x, y: origin.y)) }
            }
        }
    }
}
#endif
