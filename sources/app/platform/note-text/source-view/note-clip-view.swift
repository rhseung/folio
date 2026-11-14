import FolioDomain
import FolioMarkdown
import SwiftUI

#if os(macOS)
// 노트 끝 아래의 여백을 스크롤할 문서로 더한다. bottom content inset으로 두면 clip view가 scroll view에 남기는 띠가 되어, 텍스트 위의 클릭도 scroll view의 배경으로
// 갔다. 또 방금 연 노트가 그 띠 위까지만 그려져서, 스크롤하기 전까지 화면 아래 절반이 비고 클릭도 받지 않았다.
final class NoteClipView: NSClipView {
    override var documentRect: NSRect {
        var rect = super.documentRect
        guard let document = documentView else { return rect }
        let room = NoteOverscroll.bottom(bounds.height)
        rect.size.height = max(rect.height, document.frame.height + room)
        return rect
    }
}
#endif
