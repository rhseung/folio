import FolioDomain
import FolioMarkdown
import FolioStorage
import Foundation

@Action(
    "problem-set rm", "문제 묶음 지우기. 문제 파일과 풀이 기록은 남는다", effect: .removes,
    confirm: "문제 묶음 '{set}'을(를) 지웁니다. 문제 파일과 풀이 기록은 남습니다.", done: "문제 묶음 '{set}'을(를) 지웠습니다",
    examples: [#"folio problem-set rm "EC4207/Exercise 1" --dry-run"#], phrases: ["문제 묶음 삭제"])
public struct ProblemSetRemove {
    /// 과목
    @Arg var course: Course.ID
    /// 묶음
    @Arg var set: ProblemSet.ID

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            _ = try index(set, in: f.problemSets, .valueProblemSet)
            try f.remove(ProblemSet.self, set)
        }
    }
}
