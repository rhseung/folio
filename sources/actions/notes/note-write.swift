import FolioDomain
import FolioMarkdown
import FolioStorage
import Foundation

@Action(
    "note write", "노트 파일 전체를 바꾸기. 노트의 프로퍼티는 course.json에 있어 그대로다", done: "노트 '{note}'을(를) 썼습니다",
    phrases: ["노트 수정", "노트 내용 바꾸기"], cli: .manual(reason: "--expect의 해시를 지금 노트와 비교한 뒤 그 원문을 expected로 넘긴다"),
    // 다시 쓰기는 같은 파일의 앞선 다시 쓰기나 편집을 아무것도 남기지 않는다.
    proposal: .replaces(covers: [NoteEdit.command]), panel: true)
public struct NoteWrite {
    @Arg var course: Course.ID
    @Arg var note: Note.Path
    var text: String
    var expected: String?
    // 편집 보기가 사람이 친 글을 저장할 때 켠다. 편집 보기는 타자 중에 저장하므로, 도식 검사를 하면 반쯤 쓴 도식 때문에
    // 저장이 막힌다. 사람은 미리보기에서 도식을 보고 고친다.
    @Hidden var typed: Bool = false

    public func run(_ ctx: ActionContext) throws {
        let store = try ctx.store(course)
        let file = try FolioActions.note(ctx, course: course, path: note)
        let current = try store.read(file)
        if let expected, current != expected { throw ActionError.conflict(String(localized: .errorNoteChanged("\(note)"))) }
        if !typed { try NoteDiagramCheck.check(text, format: file.format, before: current) }
        try ctx.io(Change(.changed, ctx.relative(file.url))) { try store.write(file, text: text) }
    }
}
