import FolioDomain
import FolioMarkdown
import SwiftUI

#if os(macOS)
final class BubbleScroller: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
            // 노트의 스크롤로 바로 보낸다. responder chain으로 올리면 편집 보기로 돌아가고, 편집 보기는 말풍선 위의 휠을 다시 이 뷰로 넘긴다.
            if let note = superview?.superview as? SourceTextView {
                note.scrollNote(with: event)
            } else {
                nextResponder?.scrollWheel(with: event)
            }
            return
        }
        (superview as? PreviewBubble)?.hovered = true
        // `NSScrollView`가 처리하게 두지 않고 스와이프의 양만큼 직접 옮긴다. 노트의 scroll view 안에 들어 있고 편집 보기가 스와이프를 넘겨주는 상황에서는 `NSScrollView`가
        // 수식을 그대로 두었다. 휠 한 칸은 한 줄이다.
        guard let document = documentView else { return }
        let dx = event.hasPreciseScrollingDeltas ? event.scrollingDeltaX : event.scrollingDeltaX * NoteLook.body
        let end = max(0, document.frame.width - contentView.bounds.width)
        contentView.scroll(to: NSPoint(x: min(max(0, contentView.bounds.minX - dx), end), y: 0))
        reflectScrolledClipView(contentView)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
}
#endif
