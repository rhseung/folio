import FolioDomain
import SwiftUI

#if os(macOS)
import AppKit
import WebKit

// 포인터 아래에 옆으로 스크롤하는 것이 없을 때만 동작한다. 그렇지 않으면 넓은 PDF나 표가 가로 스크롤을 잃는다. web
// view(노트 미리보기, Claude 패널)는 넓은 표와 코드를 페이지 안에서 스크롤해 AppKit이 알 수 없으므로, web view
// 위에서는 swipe를 web view에 맡긴다.
struct SwipeNavigation: NSViewRepresentable {
    let back: @MainActor () -> Void
    let forward: @MainActor () -> Void

    func makeNSView(context: Context) -> SwipeView {
        let view = SwipeView()
        view.back = back
        view.forward = forward
        return view
    }

    func updateNSView(_ view: SwipeView, context: Context) {
        view.back = back
        view.forward = forward
    }

    static func dismantleNSView(_ view: SwipeView, coordinator: ()) { view.stop() }

    final class SwipeView: NSView {
        var back: @MainActor () -> Void = {}
        var forward: @MainActor () -> Void = {}
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .swipe]) { [weak self] event in
                nonisolated(unsafe) let event = event
                let consumed = MainActor.assumeIsolated { self?.consumes(event) ?? false }
                return consumed ? nil : event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        private func consumes(_ event: NSEvent) -> Bool {
            guard event.window === window else { return false }
            if event.type == .swipe {
                if event.deltaX > 0 { back() } else if event.deltaX < 0 { forward() }
                return true
            }
            guard event.phase == .began, NSEvent.isSwipeTrackingFromScrollEventsEnabled,
                abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY), !scrollsSideways(event)
            else { return false }
            var done = false
            event.trackSwipeEvent(options: [.lockDirection, .clampGestureAmount], dampenAmountThresholdMin: -1, max: 1) {
                [weak self] amount, phase, complete, _ in
                guard !done, phase == .ended, abs(amount) >= 1 else { return }
                done = true
                MainActor.assumeIsolated {
                    if amount > 0 { self?.back() } else { self?.forward() }
                }
            }
            return false
        }

        private func scrollsSideways(_ event: NSEvent) -> Bool {
            guard let content = window?.contentView,
                var view = content.hitTest(content.convert(event.locationInWindow, from: nil))
            else { return false }
            var ancestor: NSView? = view
            while let a = ancestor {
                if a is WKWebView { return true }
                ancestor = a.superview
            }
            while let scroll = view.enclosingScrollView {
                if let document = scroll.documentView, document.frame.width > scroll.contentView.bounds.width + 1 { return true }
                view = scroll
            }
            return false
        }
    }
}
#endif
