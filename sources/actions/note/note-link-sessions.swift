import FolioDomain
import FolioMarkdown
import FolioStorage
import Foundation

@Action(
    "note link-sessions", "복습 노트를 회차 여러 개에 연결하기. 이미 연결된 회차는 그대로 둔다", done: "노트 '{note}'에 회차를 연결했습니다",
    examples: [#"folio note link-sessions "EC4207/10-26(월) 정리" 10-26 10-28"#],
    phrases: ["복습 노트 여러 회차", "밀린 수업 한 번에 복습", "회차 여러 개 복습 노트"])
public struct NoteLinkSessions {
    /// 과목
    @Arg var course: Course.ID
    /// 복습 노트
    @Arg var note: Note.ID
    /// 회차. 예: 10-26
    @Arg var sessions: [Session.ID]

    public func run(_ ctx: ActionContext) throws {
        var meta = try FolioActions.note(ctx, course: course, id: note).meta
        guard meta.kind == .review else { throw ActionError.rule(String(localized: .errorNoteLinkSessionsKind)) }
        let file = try ctx.file(course)
        for session in sessions {
            try NoteLinks(kind: .review, session: session, exam: nil, units: []).apply(to: &meta, in: file, calendar: ctx.calendar)
        }
        try ctx.edit(course) { f in
            for session in sessions { f.linkNote(note, to: session, as: .review) }
        }
    }
}
