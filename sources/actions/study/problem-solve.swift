import FolioCore
import FolioDomain
import FolioStorage
import Foundation

@Action(
    "problem solve", "문제를 풀고 채점한 결과를 기록", effect: .logs, done: "{problem}번을 {verdict}(으)로 기록했습니다",
    examples: [
        #"folio problem solve "EC4207/Exercise 1" 2 correct --basis solution"#,
        #"folio problem solve "EC4207/Exercise 1" 3a wrong --reason concept --answer "K_{3,3}""#,
    ],
    phrases: ["풀었", "못 풀", "문제 풀이 결과", "맞았", "틀렸"], panel: true)
public struct ProblemSolve {
    /// 풀이 기록 ID. 빼면 만든다
    @Hidden var id: UUID?
    @Arg var course: Course.ID
    /// 묶음
    @Arg var set: ProblemSet.ID
    /// 문제 번호
    @Arg var problem: Problem.ID
    /// 판정: correct, partial, wrong
    @Arg var verdict: Verdict
    /// 채점 근거: key(정답), solution(풀이), claude, user(직접)
    var basis: GradeBasis = .user
    /// 푼 방법: typing, handwriting, mock
    var mode: SolveMode = .typing
    /// 낸 답
    var answer: String?
    /// 틀린 이유: concept, method, calculation, misread, time
    var reason: WrongReason?
    /// 채점이 남긴 말
    var feedback: [String] = []
    /// 한 번에 이어 푼 묶음의 ID. 섞어 풀기와 모의시험이 계획 항목을 체크한다
    @Hidden var run: UUID?

    public func run(_ ctx: ActionContext) throws {
        let s = try index(set, in: try ctx.file(course).problemSets, .valueProblemSet)
        _ = try index(problem, in: try ctx.file(course).problemSets[s].problems, .valueProblem)
        let id = id ?? UUID()
        try ctx.log(
            ProblemSolveEvent(
                id: id, setId: set, problemId: problem, mode: mode, runId: run, answer: answer, verdict: verdict, basis: basis,
                reason: verdict.isMistake ? reason : nil, feedback: feedback),
            course: course)
        ctx.made(id)
    }
}
