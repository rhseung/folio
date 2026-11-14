import FolioDomain
import FolioStorage
import Foundation

@Action(
    "session note", "회차의 러프 노트와 복습 노트. 없으면 템플릿으로 만든다", effect: .creates, done: "회차 '{session}'의 노트",
    examples: ["folio session note EC4207/10-26 review"], phrases: ["수업 노트", "강의 필기", "러프 노트", "복습 노트 열기"])
public struct SessionNote {
    /// The new note's id; unused when the note already exists.
    @New var id: Note.ID
    @Arg var course: Course.ID
    /// 회차
    @Arg var session: Session.ID
    /// rough 또는 review
    @Arg var kind: NoteKind

    public func run(_ ctx: ActionContext) throws {
        guard kind == .rough || kind == .review else { throw ActionError.rule(String(localized: .errorSessionNoteKind)) }
        let file = try ctx.file(course)
        let s = file.sessions[try index(session, in: file.sessions, .valueSession)]
        if let id = s.note(of: kind) {
            ctx.made(id)
            return
        }

        let settings = try ctx.settings()
        let title = file.noteTitle(for: s, kind: kind, calendar: ctx.calendar)
        let body = NoteTemplate.body(for: kind, title: title, sections: settings.noteSections(for: kind))
        let made = try ctx.createNote(course, title: title, meta: NoteMeta(id: id, kind: kind, math: settings.newNoteMath), body: body)
        try ctx.edit(course) { f in
            let i = try index(session, in: f.sessions, .valueSession)
            if kind == .rough {
                f.sessions[i].roughNoteId = made
            } else {
                f.sessions[i].reviewNoteId = made
                f.sessions[i].reviewNoteUnfinished = true
            }
        }
        ctx.made(made)
    }
}
