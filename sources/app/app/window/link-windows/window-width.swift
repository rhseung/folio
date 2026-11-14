import FolioDomain
import SwiftUI

#if os(macOS)
import AppKit
import WebKit

struct WindowWidth: NSViewRepresentable {
    let changed: @MainActor (CGFloat) -> Void

    func makeNSView(context: Context) -> Probe { Probe(changed: changed) }
    func updateNSView(_ view: Probe, context: Context) { view.changed = changed }

    final class Probe: NSView {
        var changed: @MainActor (CGFloat) -> Void
        private var observer: NSObjectProtocol?

        init(changed: @escaping @MainActor (CGFloat) -> Void) {
            self.changed = changed
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            guard let window else { return }
            // queue 없이 등록해야 창이 알림을 보내는 frame 변경 안에서, 창이 배치되기 전에 실행된다. queue를 주면 다음 차례까지
            // 기다린다.
            observer = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: nil) {
                [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let window = self.window else { return }
                    self.changed(window.frame.width)
                }
            }
            Task { @MainActor [weak self] in self?.changed(window.frame.width) }
        }
    }
}
#endif
