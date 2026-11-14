import FolioDomain
import Foundation

@Query(
    "score list", "과목의 점수 목록", examples: ["folio score list EC4207", "folio score list EC4207 --lines"],
    phrases: ["점수 보기", "받은 점수"], panel: true, lines: true, grades: true)
public struct ScoreList {
    /// 과목
    @Arg public var course: Course.ID

    public func read(_ ctx: ReadContext) throws -> [ScoreEntry] {
        let f = try ctx.file(course)
        let order = Dictionary(f.components.map { ($0.id, $0.order) }, uniquingKeysWith: { a, _ in a })
        return f.scores.sorted {
            (order[$0.componentId] ?? 0, $0.date?.description ?? "") < (order[$1.componentId] ?? 0, $1.date?.description ?? "")
        }
    }
}
