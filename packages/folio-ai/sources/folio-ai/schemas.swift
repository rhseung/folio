import FolioDomain
import Foundation

/// Each type carries the JSON schema
/// sent as `output_config.format`, so the schema and the decoder can't drift apart.
public protocol StructuredResult: Decodable, Sendable {
    static var schema: JSONValue { get }
}

enum Schema {
    static func object(_ properties: [String: JSONValue], required: [String]? = nil) -> JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object(properties),
            "required": .array((required ?? properties.keys.sorted()).map(JSONValue.string)),
            "additionalProperties": .bool(false),
        ])
    }
    static let string: JSONValue = .object(["type": .string("string")])
    static let integer: JSONValue = .object(["type": .string("integer")])
    static let number: JSONValue = .object(["type": .string("number")])
    static func enumeration(_ values: [String]) -> JSONValue { .object(["type": .string("string"), "enum": .array(values.map(JSONValue.string))]) }
    static func array(_ item: JSONValue) -> JSONValue { .object(["type": .string("array"), "items": item]) }
    static func nullable(_ t: JSONValue) -> JSONValue { .object(["anyOf": .array([t, .object(["type": .string("null")])])]) }
}

public struct GradingResult: StructuredResult, Equatable {
    public enum Verdict: String, Codable, Sendable { case correct, partial, wrong }
    public struct LineNote: Codable, Sendable, Equatable {
        /// 1-based line of the answer (or of the handwriting image, top to bottom).
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

/// Only a proposal: nothing moves without approval.
public struct FileClassification: StructuredResult, Equatable {
    public var role: String
    public var kind: String
    /// Course-relative standard path, file name included.
    public var suggestedPath: String
    public var week: Int?
    public var assignmentTitle: String?
    public var confident: Bool
    public var reason: String

    public static let schema = Schema.object([
        "role": Schema.enumeration(MaterialRole.allCases.map(\.rawValue)),
        "kind": Schema.enumeration(["problem", "solution", "submission", "slides", "book", "syllabus", "other"]),
        "suggestedPath": Schema.string,
        "week": Schema.nullable(Schema.integer),
        "assignmentTitle": Schema.nullable(Schema.string),
        "confident": .object(["type": .string("boolean")]),
        "reason": Schema.string,
    ])
}

public struct AssignmentExtraction: StructuredResult, Equatable {
    public var title: String
    /// ISO 8601 with offset, or null when the document has no deadline.
    public var due: String?

    public static let schema = Schema.object(["title": Schema.string, "due": Schema.nullable(Schema.string)])
}

/// The user confirms before saving.
public struct GradingPolicyExtraction: StructuredResult, Equatable {
    public struct Component: Codable, Sendable, Equatable {
        public var name: String
        public var weight: Double
        /// `sum`, `mean`, `single`, `dropLowest:N`, `bestOf:N`.
        public var aggregation: String
        public var expectedCount: Int?
    }

    public struct Cap: Codable, Sendable, Equatable {
        public var absences: Int
        public var maxGrade: String
    }

    public var components: [Component]
    public var attendanceCaps: [Cap]
    public var minAttendanceRatio: Double?
    public var latePolicy: String?
    /// Rules that don't fit the fields, quoted.
    public var notes: String

    public static let schema = Schema.object([
        "components": Schema.array(Schema.object([
            "name": Schema.string, "weight": Schema.number, "aggregation": Schema.string, "expectedCount": Schema.nullable(Schema.integer),
        ])),
        "attendanceCaps": Schema.array(Schema.object(["absences": Schema.integer, "maxGrade": Schema.string])),
        "minAttendanceRatio": Schema.nullable(Schema.number),
        "latePolicy": Schema.nullable(Schema.string),
        "notes": Schema.string,
    ])
}

extension ClaudeClient {
    public func run<T: StructuredResult>(_ task: ClaudeTask, _ type: T.Type, system: [ContentBlock], messages: [Message]) async throws -> T {
        try await structured(task, as: type, schema: T.schema, system: system, messages: messages)
    }

    /// `answerImages` are PNG pages of handwriting.
    public func grade(question: String, modelAnswer: String, rubric: [String], answer: String?, answerImages: [Data] = [],
                      rules: String) async throws -> GradingResult {
        var content: [ContentBlock] = answerImages.map { .image($0, mediaType: "image/png") }
        content.append(.text("""
        <question>\n\(question)\n</question>
        <model_answer>\n\(modelAnswer)\n</model_answer>
        <rubric>\n\(rubric.map { "- " + $0 }.joined(separator: "\n"))\n</rubric>
        <answer>\n\(answer ?? "(손글씨 이미지)")\n</answer>
        """))
        let system: [ContentBlock] = [.text("""
        You grade a university student's answer. Judge it against the rubric: an answer missing any rubric element is \
        not "correct". Use "partial" when the core idea is right but an element is missing or a step is unjustified. \
        List each missing element verbatim from the rubric. Write the feedback in Korean, at most three sentences. \
        For handwriting, number lines top to bottom across the images and point at the lines that cause problems.
        \(rules)
        """, cache: true)]
        return try await run(.grading, GradingResult.self, system: system, messages: [Message(role: .user, content: content)])
    }
}
