import FolioDomain
import FolioStorage
import Foundation

@Action(
    "component add", "성적 항목 추가. 맨 뒤에 붙는다", done: "성적 항목 '{name}'을(를) 추가했습니다",
    examples: [
        "folio component add EC4207 과제 --weight 30",
        "folio component add EC4207 퀴즈 --weight 20 --aggregation dropLowest:1 --expected-count 5 --dry-run",
    ],
    phrases: ["평가 항목 추가"])
public struct ComponentAdd {
    @New var id: GradeComponent.ID
    /// 과목
    @Arg var course: Course.ID
    /// 항목 이름
    @Arg var name: String
    /// 비중(%)
    var weight: Double
    /// 점수를 묶는 방식. sum, mean, single, dropLowest:<n>, bestOf:<n>
    var aggregation: Aggregation = .sum
    /// 예정된 점수 개수
    var expectedCount: Int?
    /// 강의계획서의 묶음 제목
    var group: String?

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            guard !f.components.contains(where: { $0.id == id }) else {
                throw ActionError.rule(String(localized: .errorIdTakenComponent("\(id)")))
            }
            let order = (f.components.map(\.order).max() ?? -1) + 1
            var c = GradeComponent(
                id: id, device: ctx.device, at: ctx.now, name: name, weight: weight, order: order, aggregation: aggregation,
                expectedCount: expectedCount)
            c.group = group
            f.components.append(c.normalized)
        }
        ctx.made(id)
    }
}
