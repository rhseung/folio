import FolioDomain
import FolioStorage
import Foundation

@Action(
    "note widget add", "노트 위젯 HTML을 .folio/widgets에 새로 쓰기. 노트에는 cb-widget 블록 {\"id\": \"<ID>\", \"height\": 320}으로 넣는다",
    discussion: "바깥 파일과 주소를 불러오는 부분이 있으면 쓰지 않는다. 위젯 환경은 folio note format.",
    effect: .creates, done: "위젯 {id}을(를) 만들었습니다",
    phrases: ["위젯 만들기", "인터랙티브 위젯", "cb-widget 추가", "위젯 HTML"])
public struct NoteWidgetAdd {
    /// 과목
    @Arg var course: Course.ID
    @New var id: NoteWidget.ID
    /// 위젯 HTML 페이지
    @FromFile("widget.html") var html: String

    public func run(_ ctx: ActionContext) throws {
        let store = try ctx.store(course)
        let path = NoteWidget.path(id)
        try Self.check(html)
        guard !FileManager.default.fileExists(atPath: store.fileURL(path).path) else {
            throw ActionError.conflict(String(localized: .errorWidgetTaken(id.uuidString)))
        }
        try ctx.io(Change(.added, try ctx.relative(course, path))) { try store.createText(path, text: html) }
        ctx.made(id)
    }

    static func check(_ html: String) throws {
        let problems = NoteWidget.problems(html)
        guard problems.isEmpty else { throw ActionError.rule(problems.map(\.message).joined(separator: "\n")) }
    }
}
