import FolioCore
import Foundation

// 바꾼 판정까지 반영한 풀이 한 번이다.
public struct ProblemAttempt: Sendable, Equatable {
    public var id: UUID
    public var at: Date
    public var day: LocalDate
    public var mode: SolveMode
    public var runId: UUID?
    public var answer: String?
    public var verdict: Verdict
    public var basis: GradeBasis
    public var reason: WrongReason?
    public var feedback: [String]
    public var changed: Bool

    public init(_ event: ProblemSolveEvent, at: Date, day: LocalDate, change: ProblemVerdictEvent? = nil) {
        id = event.id
        self.at = at
        self.day = day
        mode = event.mode
        runId = event.runId
        answer = event.answer
        verdict = change?.verdict ?? event.verdict
        basis = change == nil ? event.basis : .user
        reason = change.map { $0.verdict.isMistake ? $0.reason ?? event.reason : nil } ?? event.reason
        feedback = event.feedback
        changed = change != nil
    }
}
