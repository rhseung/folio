import FolioDomain
import FolioStorage
import Foundation

// 노트, 녹음, 다른 링크가 아무것도 가리키지 않게 되는 것은 남은 회차보다 나쁘다. 노트 폴더를 읽지 못하면 그 안의
// 노트가 어느 회차든 가리킬 수 있으므로 아무것도 지우지 않는다.
@Action(
    "session rm", "아무것도 연결되지 않은 회차 지우기",
    discussion: "노트, 녹음, 출석, 자료, 단원이 연결된 회차는 지우지 않는다(종료 코드 4). 수업이 없던 날이면 session set --kind cancelled로 휴강 표시한다.",
    effect: .removes, confirm: "회차 {sessions}을(를) 지웁니다.",
    done: "회차 {sessions}을(를) 지웠습니다", examples: ["folio session rm EC4207/10-30 --dry-run"])
public struct SessionRemove {
    @Arg var course: Course.ID
    /// 회차
    @Arg var sessions: [Session.ID]

    public func run(_ ctx: ActionContext) throws {
        let noted = Set(try ctx.notes(course).flatMap(\.meta.sessionIds))
        try ctx.edit(course) { f in
            for id in sessions {
                let s = f.sessions[try index(id, in: f.sessions, .valueSession)]
                guard f.isUnlinked(s, notedSessions: noted) else {
                    throw ActionError.rule(String(localized: .errorSessionLinked(f.title(of: s, calendar: ctx.calendar))))
                }
            }
            f.sessions.removeAll { sessions.contains($0.id) }
        }
    }
}
