import FolioCore
import FolioDomain
import FolioStorage
import Foundation

@Action(
    "problem-set set", "문제 묶음의 제목, 출처, 문제지, 풀이 바꾸기. 준 것만 바뀐다", done: "문제 묶음 '{set}'을(를) 바꿨습니다",
    examples: [#"folio problem-set set "EC4207/Exercise 1" --source textbook"#], phrases: ["문제 묶음 수정", "풀이 연결"],
    panel: true)
public struct ProblemSetSet {
    @Arg var course: Course.ID
    /// 묶음
    @Arg var set: ProblemSet.ID
    /// 새 제목
    var title: Patch<String>
    /// 출처
    var source: Patch<ProblemSource>
    /// 문제지 자료
    var material: Patch<Material.ID?>
    /// 풀이 자료
    var solution: Patch<Material.ID?>

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            try f.update(\.problemSets, set) { s in
                title.apply(&s.title)
                source.apply(&s.source)
                material.apply(&s.materialId)
                solution.apply(&s.solutionMaterialId)
                s.touch(by: ctx.device, at: ctx.now)
            }
        }
    }
}
