import FolioCore
import FolioDomain
import FolioStorage
import Foundation

@Action(
    "problem rm", "묶음에서 문제 하나 지우기. 풀이 기록은 남는다", effect: .removes, confirm: "문제 묶음 '{set}'의 {problem}번을 지웁니다. 풀이 기록은 남습니다.",
    done: "문제 묶음 '{set}'의 {problem}번을 지웠습니다", examples: [#"folio problem rm "EC4207/Exercise 1" 3a --dry-run"#], phrases: ["문제 삭제"],
    panel: true)
public struct ProblemRemove {
    @Arg var course: Course.ID
    /// 묶음
    @Arg var set: ProblemSet.ID
    /// 문제 번호
    @Arg var problem: Problem.ID

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            try f.update(\.problemSets, set) { s in
                _ = try index(problem, in: s.problems, .valueProblem)
                s.problems.removeAll { $0.id == problem }
                s.touch(by: ctx.device, at: ctx.now)
            }
        }
    }
}
