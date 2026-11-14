import FolioDomain
import FolioMarkdown
import FolioStorage
import Foundation

@Action(
    "problem-set record", "문제 풀이 결과를 기록", effect: .logs, done: "풀이를 기록했습니다",
    phrases: ["풀었", "못 풀", "문제 풀이 결과", "풀었음", "못 풂"],
    cli: .manual(reason: "묶음, 문제 번호, 판정으로 풀이 기록(ProblemAttemptEvent) 하나를 만들고 번호가 묶음에 있는지 본다"))
public struct ProblemRecord {
    @Arg var course: Course.ID
    var attempt: ProblemAttemptEvent

    public func run(_ ctx: ActionContext) throws {
        guard let set = try ctx.file(course).problemSets.first(where: { $0.id == attempt.problemSetId }) else {
            throw ActionError.notFound(String(localized: .errorNotFoundProblemSet))
        }
        guard set.problems.contains(where: { $0.number == attempt.number }) else {
            throw ActionError.notFound(String(localized: .errorNotFoundProblem(attempt.number)))
        }
        try ctx.log(attempt, course: course)
    }
}
