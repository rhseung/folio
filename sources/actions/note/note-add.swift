import FolioDomain
import FolioMarkdown
import FolioStorage
import Foundation

@Action(
    "note add", "Notes 폴더에 마크다운이나 LaTeX 노트 만들기. 본문을 주지 않으면 종류의 템플릿", effect: .creates, done: "노트 '{title}'을(를) 만들었습니다",
    examples: [
        #"folio note add EC4207 "매칭 정리" --kind topic --unit 매칭"#, #"folio note add EC4207 "매칭 정리" --format tex"#,
        ##"echo "# 메모" | folio note add EC4207 "시험 메모" --body -"##,
    ],
    phrases: ["노트 만들기", "새 노트", "정리 노트 쓰기"])
public struct NoteAdd {
    @New var id: Note.ID
    /// 과목
    @Arg var course: Course.ID
    /// 제목. 파일 이름이 된다
    @Arg var title: String
    /// 종류
    var kind: NoteKind = .free
    /// 파일 형식. markdown(.md) 또는 tex(.tex)
    var format: NoteFormat = .markdown
    /// 본문 파일. -이면 표준 입력
    @FromFile var body: String?
    /// 회차
    var session: Session.ID?
    /// 시험
    var exam: Exam.ID?
    /// 단원
    @CLIName("unit") var units: [FolioDomain.Unit.ID] = []

    public func run(_ ctx: ActionContext) throws {
        let title = title.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { throw ActionError.rule(String(localized: .errorNoteTitleEmpty)) }

        let settings = try ctx.settings()
        var meta = NoteMeta(id: id, kind: kind, math: settings.newNoteMath)
        try NoteLinks(kind: kind, session: session, exam: exam, units: units).apply(
            to: &meta, in: try ctx.file(course), calendar: ctx.calendar)
        let body = body ?? NoteTemplate.body(for: kind, title: title, sections: settings.noteSections(for: kind), format: format)
        let made = try ctx.createNote(course, title: title, meta: meta, format: format, body: body)

        if let session = meta.sessionId {
            try ctx.edit(course) { f in
                f.linkNote(made, to: session, as: kind)
                if kind == .review, let i = f.sessions.firstIndex(where: { $0.id == session }) { f.sessions[i].reviewNoteUnfinished = true }
            }
        }
        ctx.made(made)
    }
}
