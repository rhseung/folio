import FolioDomain
import FolioStorage
import Foundation

@Action(
    "note widget write", "노트 위젯 HTML 전체를 바꾸기. note widget show의 해시를 --expect로 넘겨 그사이 바뀌지 않았는지 확인한다",
    done: "위젯 {widget}을(를) 썼습니다", phrases: ["위젯 다시 쓰기", "위젯 수정"])
public struct NoteWidgetWrite {
    /// 과목
    @Arg var course: Course.ID
    /// 위젯 ID
    @Arg var widget: NoteWidget.ID
    /// 새 위젯 HTML
    @FromFile("widget.html") var html: String
    /// note widget show가 알려 준 해시. 위젯이 그사이 바뀌었으면 쓰지 않는다
    var expect: String

    public func run(_ ctx: ActionContext) throws {
        let store = try ctx.store(course)
        let path = NoteWidget.path(widget)
        try NoteWidgetAdd.check(html)
        guard FileManager.default.fileExists(atPath: store.fileURL(path).path) else {
            throw ActionError.notFound(String(localized: .errorWidgetMissing(widget.uuidString)))
        }
        guard ContentHash.of(try MaterialWrite.read(store, path)) == expect.trimmingCharacters(in: .whitespaces).lowercased() else {
            throw ActionError.conflict(String(localized: .errorWidgetChanged(widget.uuidString)))
        }
        try ctx.io(Change(.changed, try ctx.relative(course, path))) { try store.writeText(path, text: html) }
    }
}
