import FolioDomain
import FolioMarkdown
import FolioStorage
import Foundation

// 실패한 휴지통 이동이 남긴 노트는 해가 없지만 아무것도 가리키지 않는 링크는 해가 되므로, 회차가 먼저 노트와의 연결을 뗀다.
@Action(
    "note rm", "노트를 휴지통으로. 회차의 연결도 뗀다", discussion: "그림은 assets에 남는다.", effect: .removes,
    confirm: "{note}을(를) 휴지통으로 옮깁니다.", done: "{note}을(를) 휴지통으로 옮겼습니다",
    examples: [#"folio note rm "EC4207/시험 메모" --dry-run"#], phrases: ["노트 삭제"])
public struct NoteRemove {
    /// 과목
    @Arg var course: Course.ID
    /// 노트
    @Arg var note: Note.Path

    public func run(_ ctx: ActionContext) throws {
        let file = try FolioActions.note(ctx, course: course, path: note)
        if let id = file.meta.id {
            try ctx.edit(course) { f in
                f.forgetNote(id)
                f.notes.removeAll { $0.id == id }
            }
        }
        let store = try ctx.store(course)
        try ctx.io(Change(.removed, ctx.relative(file.url))) { try store.trashNote(file) }
    }
}
