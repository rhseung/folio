import FolioDomain
import FolioMarkdown
import FolioStorage
import Foundation

@Action(
    "problem-set rm", "문제 묶음 지우기. 앱이 짠 이 묶음의 계획 항목은 지워지고 직접 쓴 항목은 대상 없이 남는다. 문제 파일과 풀이 기록은 남는다", effect: .removes,
    confirm: "문제 묶음 '{set}'을(를) 지웁니다. 앱이 짠 이 묶음의 계획 항목도 지웁니다. 문제 파일과 풀이 기록은 남습니다.", done: "문제 묶음 '{set}'을(를) 지웠습니다",
    examples: [#"folio problem-set rm "EC4207/Exercise 1" --dry-run"#], phrases: ["문제 묶음 삭제"], panel: true)
public struct ProblemSetRemove {
    /// 과목
    @Arg var course: Course.ID
    /// 묶음
    @Arg var set: ProblemSet.ID

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            _ = try index(set, in: f.problemSets, .valueProblemSet)
            f.keepWrittenPlanItems(pointingTo: set)
            try f.remove(ProblemSet.self, set)
        }
    }
}
