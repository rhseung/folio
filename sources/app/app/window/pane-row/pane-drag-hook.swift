import FolioAI
import FolioDomain
import SwiftUI

#if os(macOS) && (DEBUG || RESIZE_PROBE)
// 합성한 mouse event는 실제 포인터가 움직일 때마다 drag를 잃는다. 그래서 `ResizeProbe`가 gesture와 같은 길로 구분선을
// 끈다.
@MainActor final class PaneDragHook {
    static let shared = PaneDragHook()
    var row: PaneRow?

    func move(by translation: CGFloat) { row.map { $0.dragged(0, by: translation, folded: $0.folded) } }

    func end() { row?.dropped() }
}
#endif
