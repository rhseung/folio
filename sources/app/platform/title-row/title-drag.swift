#if os(macOS)
import AppKit
import SwiftUI

// SwiftUI의 `WindowDragGesture`는 두 번 클릭을 다루지 않으므로 AppKit 뷰로 만든다.
struct TitleDrag: NSViewRepresentable {
    func makeNSView(context: Context) -> Band { Band() }
    func updateNSView(_ view: Band, context: Context) {}

    final class Band: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            if event.clickCount == 2 {
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
#endif
