import FolioCore
import FolioDomain
import FolioStorage
import Foundation

@Action(
    "problem verdict", "풀이 하나의 판정을 사용자가 바꾸기. 바꾼 판정이 최종이다", effect: .logs, done: "판정을 {verdict}(으)로 바꿨습니다",
    examples: ["folio problem verdict EC4207 3F2A9C1E-0000-4000-8000-000000000001 correct"], phrases: ["채점 바꾸기", "판정 수정", "맞은 걸로"],
    panel: true)
public struct ProblemVerdict {
    @Arg var course: Course.ID
    /// 풀이 기록 ID(folio study show --json의 attempts)
    @Arg var attempt: String
    /// 새 판정
    @Arg var verdict: Verdict
    /// 틀린 이유
    var reason: WrongReason?

    public func run(_ ctx: ActionContext) throws {
        let solves = try ctx.store(course).log.readAll().events(ProblemSolveEvent.self)
        guard let attempt = UUID(uuidString: attempt), solves.contains(where: { $0.event.id == attempt }) else {
            throw ActionError.notFound(String(localized: .errorNotFoundAttempt))
        }
        try ctx.log(ProblemVerdictEvent(attemptId: attempt, verdict: verdict, reason: verdict.isMistake ? reason : nil), course: course)
    }
}
