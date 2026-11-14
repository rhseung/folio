import Foundation

public struct QuizAttemptEvent: LogEvent, Equatable {
    public static let type = "quiz_attempt"
    public var cardId: UUID
    public var answer: String?
    public var inkId: UUID?
    public var verdict: Verdict
    public var grader: Grader
    public var missing: [String]
    public var overridden: Bool
    public var hintUsed: Bool

    public enum Grader: String, Codable, Sendable, CaseIterable { case ai, `self` }

    public init(
        cardId: UUID, answer: String? = nil, inkId: UUID? = nil, verdict: Verdict, grader: Grader, missing: [String] = [],
        overridden: Bool = false, hintUsed: Bool = false
    ) {
        self.cardId = cardId
        self.answer = answer
        self.inkId = inkId
        self.verdict = verdict
        self.grader = grader
        self.missing = missing
        self.overridden = overridden
        self.hintUsed = hintUsed
    }
}
