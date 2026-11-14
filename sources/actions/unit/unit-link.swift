import FolioDomain
import FolioStorage
import Foundation

@Action(
    "unit link", "단원에 회차 연결하기, --off면 풀기", done: "단원 '{unit}'의 회차 연결을 바꿨습니다",
    examples: ["folio unit link EC4207/트리 10-26 10-28", "folio unit link EC4207/트리 10-28 --off --dry-run"],
    phrases: ["단원과 수업 연결", "이 수업에서 배운 단원"])
public struct UnitLink {
    @Arg var course: Course.ID
    /// 단원
    @Arg var unit: FolioDomain.Unit.ID
    /// 회차. 예: 10-26
    @Arg var sessions: [Session.ID]
    /// 연결 풀기
    @Off("off") var linked = true

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            let u = try index(unit, in: f.units, .valueUnit)
            for session in sessions {
                _ = try index(session, in: f.sessions, .valueSession)
                if f.units[u].sessionIds.contains(session) != linked { f.toggle(session: session, unit: unit) }
            }
        }
    }
}
