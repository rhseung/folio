import SwiftUI

#if os(macOS)
import AppKit
#endif

// 끄는 탭은 그 탭을 누른 창의 제스처만 받으므로, 다른 창에 놓을 자리는 모든 창의 탭 줄을 모아 둔 이곳에서 찾는다.
@MainActor final class TabDragHub {
    static let shared = TabDragHub()

    private var windows: [Weak] = []
    private weak var shown: TabDrag?
    private var placements: [UUID: CGRect] = [:]

    private struct Weak {
        weak var drag: TabDrag?
    }

    func register(_ drag: TabDrag) {
        windows = windows.filter { $0.drag != nil && $0.drag !== drag } + [Weak(drag: drag)]
    }

    #if os(macOS)
    // 포인터 아래의 맨 앞 창을 고른다. 다른 앱의 창이나 Folio의 다른 종류 창이 앞에 있으면 놓을 Folio 창이 없다.
    func target(atScreen point: CGPoint) -> (drag: TabDrag, point: CGPoint)? {
        let number = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)
        guard let drag = windows.lazy.compactMap(\.drag).first(where: { $0.window?.windowNumber == number }),
            let window = drag.window, let view = window.contentView
        else { return nil }
        let local = view.convert(window.convertPoint(fromScreen: point), from: nil)
        return (drag, CGPoint(x: local.x, y: view.isFlipped ? local.y : view.bounds.height - local.y))
    }
    #endif

    // 미리 보이는 창은 한 번에 하나다. 포인터가 다른 창으로 옮겨 가면 앞 창의 표시를 지운다.
    func show(_ place: TabDrop, in target: TabDrag?, caret: CGFloat?) {
        if let shown, shown !== target { shown.clearPreview() }
        shown = target
        target?.preview(place, caret: caret)
    }

    func clear() {
        shown?.clearPreview()
        shown = nil
    }

    // 창의 자리는 이번 실행에서 떼어 낸 창에만 준다. `WindowRequest`에 넣으면 다시 실행해 복원한 창도 오래전 자리로 옮긴다.
    func place(_ request: UUID, at frame: CGRect) { placements[request] = frame }

    func placement(for request: UUID) -> CGRect? { placements.removeValue(forKey: request) }
}
