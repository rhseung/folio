#if os(macOS)
import AppKit
import SwiftUI

extension View {
    /// The first run is a small landing window of its own size, as in the mockup; the app is a large resizable one.
    func mainWindowFrame(firstRun: Bool) -> some View { modifier(MainWindowFrame(firstRun: firstRun)) }
}

private struct MainWindowFrame: ViewModifier {
    let firstRun: Bool
    @State private var host = WindowHost()
    /// The window's frame before the first run shrank it, to go back to: the saved frame on a first launch, the frame
    /// it had when the first run was opened again from settings.
    @State private var before: NSRect?
    /// The system title bar's height. The first run draws under it, but the window counts it outside the content, so
    /// the content is this much shorter than the window the mockup gives.
    @State private var titleBar: CGFloat = 0

    func body(content: Content) -> some View {
        let small = CGSize(width: Theme.Size.firstRunWindow.width, height: Theme.Size.firstRunWindow.height - titleBar)
        let least = Theme.Size.windowMin
        // One frame whose bounds change, not two branches: a branch would rebuild the root view and lose its tabs.
        // Bounded both ways, so the window's least size is this frame's own: with only a least size the hosting view
        // measured the whole window's content for it on every layout of a resize or a drag (#62).
        content
            .frame(
                minWidth: firstRun ? small.width : least.width, maxWidth: firstRun ? small.width : .infinity,
                minHeight: firstRun ? small.height : least.height, maxHeight: firstRun ? small.height : .infinity
            )
            .background(
                WindowReader { window in
                    host.window = window
                    titleBar = window.frame.height - window.contentLayoutRect.height
                    fit(window, animate: false)
                }
            )
            .onChange(of: firstRun) {
                guard let window = host.window else { return }
                fit(window, animate: true)
            }
    }

    private func fit(_ window: NSWindow, animate: Bool) {
        // After SwiftUI has applied the new bounds to the window, which would otherwise hold it at the old ones.
        DispatchQueue.main.async {
            guard !window.styleMask.contains(.fullScreen), let screen = window.screen ?? NSScreen.main else { return }
            let visible = screen.visibleFrame
            let frame: NSRect
            let small = Theme.Size.firstRunWindow
            if firstRun {
                guard window.frame.size != small else { return }
                before = window.frame
                frame = centered(small, in: visible)
            } else {
                guard window.frame.size == small else { return }
                frame =
                    before
                    ?? centered(
                        window.frameRect(forContentRect: NSRect(origin: .zero, size: WindowSize.opening(in: visible.size))).size,
                        in: visible)
                before = nil
            }
            window.setFrame(frame, display: true, animate: animate)
        }
    }

    private func centered(_ size: CGSize, in visible: NSRect) -> NSRect {
        NSRect(
            x: (visible.midX - size.width / 2).rounded(), y: (visible.midY - size.height / 2).rounded(),
            width: size.width, height: size.height)
    }
}
#endif
