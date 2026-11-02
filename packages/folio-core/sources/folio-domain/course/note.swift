import Foundation

public enum NoteKind: String, Codable, Sendable, CaseIterable {
    case rough, review
    case examSummary = "exam_summary"
    case topic, free
}

/// Notes without the frontmatter key are LaTeX, as Obsidian and Notion write them.
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

public enum NoteFormat: String, Codable, Sendable, CaseIterable {
    case markdown, tex

    public var fileExtension: String {
        switch self {
        case .markdown: "md"
        case .tex: "tex"
        }
    }

    public init?(path: String) {
        guard let format = Self.allCases.first(where: { $0.fileExtension == (path as NSString).pathExtension.lowercased() }) else { return nil }
        self = format
    }
}

/// A note's properties, kept in course.json beside its path instead of in the file. A `.tex` file has no place for
/// them that TeX and other editors leave alone, and keeping them out of both formats lets the two work the same way.
public struct NoteEntry: Entity {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var updatedBy: DeviceID

    /// Relative to the course folder, `/`-separated, like a material's.
    public var path: String
    public var kind: NoteKind
    public var sessionId: UUID?
    public var unitIds: [UUID]
    public var examId: UUID?
    public var tags: [String]
    public var math: MathSyntax

    public init(id: UUID, device: DeviceID, at date: Date, path: String, meta: NoteMeta) {
        self.id = id
        createdAt = date
        updatedAt = date
        updatedBy = device
        self.path = path
        kind = meta.kind
        sessionId = meta.sessionId
        unitIds = meta.unitIds
        examId = meta.examId
        tags = meta.tags
        math = meta.math
    }

    public var meta: NoteMeta {
        NoteMeta(id: id, kind: kind, sessionId: sessionId, unitIds: unitIds, examId: examId, tags: tags, math: math)
    }

    /// Everything but the id, which an entry keeps for life.
    public mutating func apply(_ meta: NoteMeta) {
        kind = meta.kind
        sessionId = meta.sessionId
        unitIds = meta.unitIds
        examId = meta.examId
        tags = meta.tags
        math = meta.math
    }
}

/// Note bodies. Settings may override the section headings; these are the defaults.
public enum NoteTemplate {
    public static func defaultSections(for kind: NoteKind) -> [String] {
        switch kind {
        case .rough, .free: []
        case .review: ["이번 회차의 단원", "핵심 정의와 정리", "예시", "모르는 것"]
        case .examSummary: ["시험 범위", "단원별 요약", "자주 틀리는 것", "공식과 정리 모음"]
        case .topic: ["정의", "정리와 증명", "예시와 반례", "관련 단원"]
        }
    }

    public static func body(for kind: NoteKind, title: String, sections: [String]? = nil, format: NoteFormat = .markdown) -> String {
        let sections = sections ?? defaultSections(for: kind)
        switch format {
        case .markdown:
            return (["# \(title)"] + sections.map { "\n## \($0)\n" }).joined(separator: "\n") + "\n"
        case .tex:
            // kotex because notes are Korean; the AMS packages because most notes are math.
            let preamble = ["\\documentclass[11pt]{article}", "\\usepackage{kotex}", "\\usepackage{amsmath, amssymb, amsthm}", "", "\\begin{document}", ""]
            let heading = ["\\section*{\(texEscaped(title))}", ""]
            let parts = sections.flatMap { ["\\subsection*{\(texEscaped($0))}", "", ""] }
            return (preamble + heading + parts + ["\\end{document}"]).joined(separator: "\n") + "\n"
        }
    }

    /// A title is plain text, so TeX's special characters in it are written as themselves.
    static func texEscaped(_ text: String) -> String {
        text.map { c -> String in
            switch c {
            case "\\": "\\textbackslash{}"
            case "~": "\\textasciitilde{}"
            case "^": "\\textasciicircum{}"
            case "#", "$", "%", "&", "_", "{", "}": "\\\(c)"
            default: String(c)
            }
        }.joined()
    }
}

/// Notes are files, not rows in a document, so they have no entity type; this names their id where an action points
/// at one (`Note.ID`), the way `Exam.ID` does.
public enum Note {
    public typealias ID = UUID
    /// Course-relative, for actions that work on a note's file whether or not it has an id yet.
    public typealias Path = String
}
