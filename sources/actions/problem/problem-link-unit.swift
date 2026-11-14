import FolioDomain
import FolioMarkdown
import FolioStorage
import Foundation

@Action(
    "problem-set link", "문제를 단원에 연결하거나 떼기", done: "문제 묶음 '{set}'의 {number}번과 단원 '{unit}'의 연결을 바꿨습니다",
    examples: [#"folio problem-set link "EC4207/Exercise 1" 3a 매칭"#, #"folio problem-set link "EC4207/Exercise 1" 3a 매칭 --off"#],
    phrases: ["문제 단원 연결"])
public struct ProblemLinkUnit {
    /// 과목
    @Arg var course: Course.ID
    /// 묶음
    @Arg var set: ProblemSet.ID
    /// 문제 번호
    @Arg var number: String
    /// 같은 과목의 단원
    @Arg var unit: FolioDomain.Unit.ID
    /// 연결 떼기
    @Off("off") var linked = true

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            let s = try index(set, in: f.problemSets, .valueProblemSet)
            _ = try index(unit, in: f.units, .valueUnit)
            guard let p = f.problemSets[s].problems.firstIndex(where: { $0.number == number }) else {
                throw ActionError.notFound(String(localized: .errorNotFoundProblem(number)))
            }
            guard f.problemSets[s].problems[p].unitIds.contains(unit) != linked else { return }
            if linked {
                f.problemSets[s].problems[p].unitIds.append(unit)
            } else {
                f.problemSets[s].problems[p].unitIds.removeAll { $0 == unit }
            }
            f.problemSets[s].touch(by: ctx.device, at: ctx.now)
        }
    }
}
