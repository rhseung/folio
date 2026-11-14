import FolioDomain
import Foundation

public struct GradingResult: StructuredResult, Equatable {
    public enum Verdict: String, Codable, Sendable { case correct, partial, wrong }
    public struct LineNote: Codable, Sendable, Equatable {
        public var line: Int
        public var note: String
    }

    public var verdict: Verdict
    public var missing: [String]
    public var feedback: String
    public var lines: [LineNote]

    public static let schema = Schema.object([
        "verdict": Schema.enumeration(["correct", "partial", "wrong"]),
        "missing": Schema.array(Schema.string),
        "feedback": Schema.string,
        "lines": Schema.array(Schema.object(["line": Schema.integer, "note": Schema.string])),
    ])
}
