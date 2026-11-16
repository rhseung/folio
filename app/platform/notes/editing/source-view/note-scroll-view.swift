import FolioDomain
import FolioMarkdown
import SwiftUI

#if os(macOS)
final class NoteScrollView: NSScrollView {
    init(document: NSTextView) {
        super.init(frame: .zero)
        hasVerticalScroller = true
        autohidesScrollers = true
        drawsBackground = false
        borderType = .noBorder
        contentView = NoteClipView()
        findBarPosition = .aboveContent
        document.minSize = .zero
        document.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        document.isVerticallyResizable = true
        document.isHorizontallyResizable = false
        document.autoresizingMask = [.width]
        documentView = document
        contentView.postsBoundsChangedNotifications = true
        automaticallyAdjustsContentInsets = false
        documentCursor = .iBeam
    }

    required init?(coder: NSCoder) { fatalError() }

    #if DEBUG
    private(set) var wheels = 0

    override func scrollWheel(with event: NSEvent) {
        wheels += 1
        super.scrollWheel(with: event)
    }
    #endif

    // 노트 위의 모든 클릭은 AppKit의 hit test 결과와 상관없이 여기로 보낸다. 기본 clip view에서는 scroll view가 문서 위의 클릭을 직접 가져갔고, `NoteClipView`에서는
    // 가장 깊은 뷰를 돌려준다. 노트가 텍스트 위에 올린 뷰(미리보기 말풍선)는 클릭을 받지 않는다. 노트 끝 아래의 여백은 노트의 어느 부분에도 속하지 않는 clip view의 영역이라 클릭이 아무 데도 가지
    // 않았으므로, 노트가 받아 캐럿을 끝에 둔다.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        guard let hit, let document = documentView, hit === self || hit === contentView || hit.isDescendant(of: document) else {
            return hit
        }
        return document
    }
}
#endif
