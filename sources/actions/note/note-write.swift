import FolioDomain
import FolioMarkdown
import FolioStorage
import Foundation

@Action(
    "note write", "노트 파일 전체를 바꾸기. 노트의 프로퍼티는 course.json에 있어 그대로다", done: "노트 '{note}'을(를) 썼습니다",
    phrases: ["노트 수정", "노트 내용 바꾸기"], cli: .manual(reason: "--expect의 해시를 지금 노트와 비교한 뒤 그 원문을 expected로 넘긴다"))
public struct NoteWrite {
    @Arg var course: Course.ID
    @Arg var note: Note.Path
    var text: String
    var expected: String?

    public func run(_ ctx: ActionContext) throws {
        let store = try ctx.store(course)
        let file = try FolioActions.note(ctx, course: course, path: note)
        if let expected, try store.read(file) != expected { throw ActionError.conflict(String(localized: .errorNoteChanged("\(note)"))) }
        try ctx.io(Change(.changed, ctx.relative(file.url))) { try store.write(file, text: text) }
    }
}
