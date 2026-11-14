import FolioDomain
import FolioMarkdown
import FolioStorage
import Foundation

@Action(
    "note adopt", "Folio 밖에서 만든 노트에 ID 붙이기", done: "노트 '{note}'에 ID를 붙였습니다",
    examples: ["folio note adopt EC4207/Notes/외부.md"], phrases: ["밖에서 만든 노트 등록"])
public struct NoteAdopt {
    /// 과목
    @Arg var course: Course.ID
    /// 노트
    @Arg var note: Note.Path

    public func run(_ ctx: ActionContext) throws {
        let file = try FolioActions.note(ctx, course: course, path: note)
        if let id = file.meta.id {
            ctx.made(id)
            return
        }
        let store = try ctx.store(course)
        let id = UUID()
        try ctx.edit(course) {
            $0.notes.append(NoteEntry(id: id, device: ctx.device, at: ctx.now, path: store.notePath(of: file.url), meta: NoteMeta(id: id)))
        }
        ctx.made(id)
    }
}
