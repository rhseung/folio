import FolioDomain
import FolioMarkdown
import FolioStorage
import Foundation

@Action(
    "note unlink-session", "회차 하나에서 노트 떼기. 노트가 맡은 다른 회차는 그대로 둔다", done: "회차 '{session}'에서 노트 '{note}'을(를) 뗐습니다",
    examples: [#"folio note unlink-session "EC4207/10-26(월) 정리" 10-26"#], phrases: ["복습 노트 회차 빼기", "노트 회차 연결 풀기"])
public struct NoteUnlinkSession {
    /// 과목
    @Arg var course: Course.ID
    /// 노트
    @Arg var note: Note.ID
    /// 회차
    @Arg var session: Session.ID

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            guard f.notes.contains(where: { $0.id == note }) else {
                throw ActionError.notFound(String(localized: .errorNotFoundNote("\(note)")))
            }
            let s = f.sessions[try index(session, in: f.sessions, .valueSession)]
            guard s.roughNoteId == note || s.reviewNoteId == note else {
                throw ActionError.rule(String(localized: .errorNoteSessionNotLinked(f.title(of: s, calendar: ctx.calendar))))
            }
            f.unlinkNote(note, from: session)
        }
    }
}
