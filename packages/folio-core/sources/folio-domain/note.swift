import Foundation

public enum NoteKind: String, Codable, Sendable, CaseIterable {
    case rough, review
    case examSummary = "exam_summary"
    case topic, free
}

/// Note metadata, stored in the markdown file's frontmatter (docs/SPEC.md "Note").
/// How `$…$` in a note is written. Notes without the frontmatter key are LaTeX, as Obsidian and Notion write them.
public enum MathSyntax: String, Codable, Sendable, CaseIterable {
    case latex, asciimath
}

public struct NoteMeta: Equatable, Sendable {
    /// Nil for markdown that hasn't been given an ID yet (e.g. moved in from an old 노트 folder).
    public var id: UUID?
    public var kind: NoteKind
    public var sessionId: UUID?
    public var unitIds: [UUID]
    public var examId: UUID?
    public var tags: [String]
    public var math: MathSyntax

    public init(id: UUID? = UUID(), kind: NoteKind = .free, sessionId: UUID? = nil, unitIds: [UUID] = [], examId: UUID? = nil, tags: [String] = [],
                math: MathSyntax = .latex) {
        self.id = id
        self.kind = kind
        self.sessionId = sessionId
        self.unitIds = unitIds
        self.examId = examId
        self.tags = tags
        self.math = math
    }
}

/// Note bodies (docs/SPEC.md "노트 템플릿"). Settings may override the section headings; these are the defaults.
public enum NoteTemplate {
    public static func defaultSections(for kind: NoteKind) -> [String] {
        switch kind {
        case .rough, .free: []
        case .review: ["이번 회차의 단원", "핵심 정의와 정리", "예시", "모르는 것"]
        case .examSummary: ["시험 범위", "단원별 요약", "자주 틀리는 것", "공식과 정리 모음"]
        case .topic: ["정의", "정리와 증명", "예시와 반례", "관련 단원"]
        }
    }

    public static func body(for kind: NoteKind, title: String, sections: [String]? = nil) -> String {
        (["# \(title)"] + (sections ?? defaultSections(for: kind)).map { "\n## \($0)\n" }).joined(separator: "\n") + "\n"
    }
}

/// Notes are files, not rows in a document, so they have no entity type; this names their id where an action points
/// at one (`Note.ID`), the way `Exam.ID` does.
public enum Note {
    public typealias ID = UUID
    /// Course-relative, for actions that work on a note's file whether or not it has an id yet.
    public typealias Path = String
}
