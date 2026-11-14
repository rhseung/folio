import FolioDomain
import FolioStorage
import Foundation

@Action(
    "unit move", "단원을 형제 사이에서 옮기거나 다른 단원 아래로 옮기기", done: "단원 '{unit}'을(를) 옮겼습니다",
    cli: .manual(reason: "--up, --down, --parent, --top 중 하나가 옮길 곳(Target) 하나가 된다"))
public struct UnitMove {
    public enum Target: Codable, Sendable, Equatable {
        case by(Int), parent(UUID?)
        // `folio actions --schema`가 모든 케이스를 나열하도록 CaseIterable을 붙인다. Codable 합성은 여전히 이 키를 쓴다.
        enum CodingKeys: CodingKey, CaseIterable { case by, parent }
    }
    @Arg var course: Course.ID
    @Arg var unit: FolioDomain.Unit.ID
    var target: Target

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            _ = try index(unit, in: f.units, .valueUnit)
            switch target {
            case .by(let offset): _ = UnitTree.move(unit, by: offset, in: &f.units)
            case .parent(let parent):
                guard UnitTree.setParent(unit, to: parent, in: &f.units) else { throw ActionError.rule(String(localized: .errorUnitCycle)) }
            }
        }
    }
}
