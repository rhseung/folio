import FolioCore
import Foundation

// 풀이 한 번이다. 기기별 로그에 한 줄로 쓴다.
public struct ProblemSolveEvent: LogEvent, Equatable {
    public static let type = "problem_solve"
    public var id: UUID
    public var setId: UUID
    public var problemId: UUID
    public var mode: SolveMode
    // 모의시험이나 필기 묶음처럼 함께 낸 풀이를 묶는다.
    public var runId: UUID?
    public var answer: String?
    // 참거짓에 붙인 이유 한 줄이다. 채점에는 쓰지 않고 나중에 다시 볼 때 보인다.
    public var why: String?
    public var verdict: Verdict
    public var basis: GradeBasis
    public var reason: WrongReason?
    public var feedback: [String]

    public init(
        id: UUID = UUID(), setId: UUID, problemId: UUID, mode: SolveMode = .typing, runId: UUID? = nil, answer: String? = nil,
        why: String? = nil, verdict: Verdict, basis: GradeBasis, reason: WrongReason? = nil, feedback: [String] = []
    ) {
        self.id = id
        self.setId = setId
        self.problemId = problemId
        self.mode = mode
        self.runId = runId
        self.answer = answer
        self.why = why
        self.verdict = verdict
        self.basis = basis
        self.reason = reason
        self.feedback = feedback
    }
}
