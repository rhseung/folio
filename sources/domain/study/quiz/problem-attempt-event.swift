import Foundation

public struct ProblemAttemptEvent: LogEvent, Equatable {
    public static let type = "problem_attempt"
    public var problemSetId: UUID
    public var number: String
    public var verdict: Verdict
    public var inkId: UUID?

    public init(problemSetId: UUID, number: String, verdict: Verdict, inkId: UUID? = nil) {
        self.problemSetId = problemSetId
        self.number = number
        self.verdict = verdict
        self.inkId = inkId
    }
}
