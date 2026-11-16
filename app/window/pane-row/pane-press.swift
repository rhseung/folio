import FolioAI
import FolioDomain
import SwiftUI

#if os(macOS)
import AppKit

// gesture가 아니라 local event monitor를 쓴다. 노트의 글, 미리보기 페이지, PDF는 SwiftUI보다 먼저 AppKit에서 클릭을
// 받기 때문이다. 이 monitor는 클릭을 가져가지 않는다.
struct PanePress: NSViewRepresentable {
    let active: Bool
    var clicks = 1
    let press: @MainActor () -> Void

    func makeNSView(context: Context) -> Probe { Probe(press: press) }

    func updateNSView(_ view: Probe, context: Context) {
        view.active = active
        view.clicks = clicks
        view.press = press
    }

    final class Probe: NSView {
        var active = false
        var clicks = 1
        var press: @MainActor () -> Void
        private var monitor: Any?

        init(press: @escaping @MainActor () -> Void) {
            self.press = press
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
                // local monitor는 앱이 처리하는 event와 함께 main thread에서 실행된다.
                nonisolated(unsafe) let event = event
                MainActor.assumeIsolated { self?.check(event) }
                return event
            }
        }

        private func check(_ event: NSEvent) {
            guard active, let window, event.window === window, !isHiddenOrHasHiddenAncestor,
                clicks == 1 || (event.type == .leftMouseDown && event.clickCount == clicks),
                bounds.contains(convert(event.locationInWindow, from: nil))
            else { return }
            press()
        }
    }
}
#endif
