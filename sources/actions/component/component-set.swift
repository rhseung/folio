import FolioDomain
import FolioStorage
import Foundation

@Action(
    "component set", "성적 항목 고치기. 준 것만 바꾼다", done: "성적 항목 '{component}'을(를) 고쳤습니다",
    examples: [
        "folio component set EC4207/과제 --weight 25", "folio component set EC4207/퀴즈 --aggregation bestOf:3",
        "folio component set EC4207/퀴즈 --group none --dry-run",
    ],
    phrases: ["비율 바꾸기", "반영 비율", "항목 이름"])
public struct ComponentSet {
    @Arg var course: Course.ID
    /// 항목 이름
    @Arg var component: GradeComponent.ID
    /// 이름
    var name: Patch<String>
    /// 비중(%)
    var weight: Patch<Double>
    /// 점수를 묶는 방식
    var aggregation: Patch<Aggregation>
    /// 예정된 점수 개수
    var expectedCount: Patch<Int?>
    /// 강의계획서의 묶음 제목
    var group: Patch<String?>

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            try f.update(\.components, component) { c in
                name.apply(&c.name)
                weight.apply(&c.weight)
                aggregation.apply(&c.aggregation)
                expectedCount.apply(&c.expectedCount)
                group.apply(&c.group)
                c = c.normalized
                c.touch(by: ctx.device, at: ctx.now)
            }
        }
    }
}
