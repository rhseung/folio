import FolioDomain
import FolioStorage
import Foundation

@Action(
    "unit rm", "단원 지우기. 하위 단원은 한 단계 올라간다. 회차, 시험 범위, 자료, 노트, 문제의 연결은 풀린다. 그 단원의 정리 노트 만들기 계획 항목은 지워진다. 노트와 카드 파일은 남는다",
    effect: .removes,
    confirm: "단원 '{unit}'을(를) 지우고 회차, 시험 범위, 자료, 노트, 문제의 연결을 풉니다.", done: "단원 '{unit}'을(를) 지웠습니다",
    examples: ["folio unit rm EC4207/트리 --dry-run"], phrases: ["단원 삭제"], panel: true)
public struct UnitRemove {
    @Arg var course: Course.ID
    /// 단원
    @Arg var unit: FolioDomain.Unit.ID

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            _ = try index(unit, in: f.units, .valueUnit)
            try f.remove(FolioDomain.Unit.self, unit)
        }
    }
}
