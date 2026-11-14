import FolioDomain
import FolioStorage
import Foundation

@Query(
    "note widget show", "위젯 HTML 원문. --json에는 note widget write --expect에 넘길 해시가 있다", phrases: ["위젯 원문", "위젯 HTML 보기"],
    panel: true)
public struct NoteWidgetShow {
    @Arg public var course: Course.ID
    /// 위젯 ID
    @Arg public var widget: NoteWidget.ID

    public func read(_ ctx: ReadContext) throws -> NoteFileBody {
        NoteFileBody(
            name: widget.uuidString, path: NoteWidget.path(widget),
            text: try MaterialText.read(try ctx.store(course), NoteWidget.path(widget)))
    }
}
