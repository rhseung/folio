import FolioDomain
import FolioMarkdown
import FolioStorage
import Foundation

@Action(
    "note link", "노트의 종류와 회차, 시험, 단원 연결, 수식 문법 정하기",
    discussion: """
        러프 노트와 복습 노트는 --session, 시험 종합 정리는 --exam, 단원 노트(topic)는 --unit을 받는다. 종류를 바꾸면 예전 연결은 떨어진다.
        복습 노트는 --session의 회차를 옮기지 않고 더한다. 여러 회차를 한 번에 더할 때는 note link-sessions, 회차 하나를 뗄 때는 note unlink-session을 쓴다.
        """,
    done: "노트 '{note}'을(를) 연결했습니다",
    examples: [
        "folio note link EC4207/09-08 --kind review --session 09-08",
        #"folio note link "EC4207/매칭 정리" --kind topic --unit 매칭 --unit "이분 그래프""#,
    ],
    phrases: ["노트 연결", "노트 종류"])
public struct NoteLink {
    @Arg var course: Course.ID
    /// 노트
    @Arg var note: Note.ID
    /// 종류
    var kind: NoteKind
    /// 회차
    var session: Session.ID?
    /// 시험
    var exam: Exam.ID?
    /// 단원
    @CLIName("unit") var units: [FolioDomain.Unit.ID] = []
    /// 수식 문법. 빼면 그대로
    var math: MathSyntax?

    public func run(_ ctx: ActionContext) throws {
        var meta = try FolioActions.note(ctx, course: self.course, id: note).meta
        try NoteLinks(kind: kind, session: session, exam: exam, units: units).apply(
            to: &meta, in: try ctx.file(self.course), calendar: ctx.calendar)
        meta.math = math ?? meta.math
        try ctx.edit(self.course) { f in
            guard let i = f.notes.firstIndex(where: { $0.id == note }) else { return }
            f.notes[i].apply(meta)
            f.notes[i].touch(by: ctx.device, at: ctx.now)
            f.linkNote(note, to: meta.sessionId, as: kind)
        }
    }
}
