import FolioCore
import FolioDomain
import Foundation

public struct ProblemGrade: StructuredResult, Equatable {
    public struct LineNote: Codable, Sendable, Equatable {
        public var line: Int
        public var note: String
    }

    public var verdict: Verdict
    public var reason: WrongReason?
    public var feedback: [String]
    public var lines: [LineNote]

    public init(verdict: Verdict, reason: WrongReason? = nil, feedback: [String] = [], lines: [LineNote] = []) {
        self.verdict = verdict
        self.reason = reason
        self.feedback = feedback
        self.lines = lines
    }

    public static let schema = Schema.object([
        "verdict": Schema.enumeration(["correct", "partial", "wrong"]),
        "reason": Schema.nullable(Schema.enumeration(WrongReason.allCases.map(\.rawValue))),
        "feedback": Schema.array(Schema.string),
        "lines": Schema.array(Schema.object(["line": Schema.integer, "note": Schema.string])),
    ])
}
