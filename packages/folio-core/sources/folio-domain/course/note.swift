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
    /// In date order. A review note may cover several classes caught up on at once; a rough note has one.
    public var sessionIds: [UUID]
    public var unitIds: [UUID]
    public var examId: UUID?
    public var tags: [String]
    public var math: MathSyntax

    public init(id: UUID? = UUID(), kind: NoteKind = .free, sessionId: UUID? = nil, unitIds: [UUID] = [], examId: UUID? = nil, tags: [String] = [],
                math: MathSyntax = .latex) {
        self.id = id
        self.kind = kind
        self.sessionIds = sessionId.map { [$0] } ?? []
        self.unitIds = unitIds
        self.examId = examId
        self.tags = tags
        self.math = math
    }

    /// The first session, or setting the only one. Old frontmatter and the action inputs name a single session.
    public var sessionId: UUID? {
        get { sessionIds.first }
        set { sessionIds = newValue.map { [$0] } ?? [] }
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
/// The note's sessions are not stored here: the sessions pointing at it say so (`Session.roughNoteId`, `reviewNoteId`),
/// and a second copy here drifted from them. Read the links through `CourseFile.meta(of:)`.
public struct NoteEntry: Entity {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var updatedBy: DeviceID

    /// Relative to the course folder, `/`-separated, like a material's.
    public var path: String
    public var kind: NoteKind
    /// A topic note's own units. Other kinds take theirs from their session or exam, so they store none.
    public var unitIds: [UUID]
    public var examId: UUID?
    public var tags: [String]
    public var math: MathSyntax
    /// The hash of the PDF `note build` last wrote. A different file in that place is someone else's export.
    public var builtHash: String?

    public init(id: UUID, device: DeviceID, at date: Date, path: String, meta: NoteMeta) {
        self.id = id
        createdAt = date
        updatedAt = date
        updatedBy = device
        self.path = path
        kind = meta.kind
        unitIds = []
        tags = []
        math = meta.math
        apply(meta)
    }

    /// Everything but the id, which an entry keeps for life, and the session, which the session holds.
    public mutating func apply(_ meta: NoteMeta) {
        kind = meta.kind
        unitIds = meta.kind == .topic ? meta.unitIds : []
        examId = meta.examId
        tags = meta.tags
        math = meta.math
    }
}

extension CourseFile {
    /// A note's links as they read now: its sessions are the ones pointing at it, and its units are theirs or the
    /// exam's scope as they are today, so unlinking a session from a unit takes its notes off that unit too.
    public func meta(of entry: NoteEntry) -> NoteMeta {
        let sessions = sessions(pointingAt: entry.id)
        let units: [UUID] = switch entry.kind {
        case .topic: entry.unitIds
        case .rough, .review: UnitTree.outline(self.units).map(\.unit).filter { u in sessions.contains { u.sessionIds.contains($0.id) } }.map(\.id)
        case .examSummary: exams.first { $0.id == entry.examId }?.scopeUnitIds ?? []
        case .free: []
        }
        var meta = NoteMeta(id: entry.id, kind: entry.kind, unitIds: units, examId: entry.examId, tags: entry.tags, math: entry.math)
        meta.sessionIds = sessions.map(\.id)
        return meta
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
            let heading = ["", "\\section*{\(texEscaped(title))}", ""]
            let parts = sections.flatMap { ["\\subsection*{\(texEscaped($0))}", "", ""] }
            return TexDocument.wrap(heading + parts)
        }
    }

    /// `text` with the heading `body(for:title:)` wrote changed from `old` to `new`. Only the first top heading, and
    /// only when it still reads `old`: one the user rewrote is theirs.
    public static func retitled(_ text: String, from old: String, to new: String, format: NoteFormat) -> String {
        let (heading, replacement) = switch format {
        case .markdown: ("# \(old)", "# \(new)")
        case .tex: ("\\section*{\(texEscaped(old))}", "\\section*{\(texEscaped(new))}")
        }
        var lines = text.components(separatedBy: "\n")
        let isTop: (String) -> Bool = format == .markdown ? { $0.hasPrefix("# ") } : { $0.hasPrefix("\\section") }
        guard let i = lines.firstIndex(where: { isTop($0.trimmingCharacters(in: .whitespaces)) }),
              lines[i].trimmingCharacters(in: .whitespaces) == heading else { return text }
        lines[i] = replacement
        return lines.joined(separator: "\n")
    }

    /// `text` of a note moved from the folder `old` to `new` (paths in the course folder), with the paths it gives
    /// relative to its own folder still reaching the same files: `![](assets/a.png)` written in `Notes` reads
    /// `![](../assets/a.png)` in `Notes/정리`. The preview and TeX resolve them from the note's folder, so a move would
    /// otherwise break every picture. Links with a scheme, absolute paths, anchors, and paths that climb out of the
    /// course stay as written.
    public static func rebased(_ text: String, from old: String, to new: String, format: NoteFormat) -> String {
        guard old != new else { return text }
        func rebase(_ path: String) -> String? {
            guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("#"), !path.contains("://"),
                  path.firstIndex(of: ":").map({ colon in !path[..<colon].contains("/") }) != true else { return nil }
            let cut = path.firstIndex { $0 == "#" || $0 == "?" } ?? path.endIndex
            var target = old.split(separator: "/").map(String.init)
            for part in path[..<cut].split(separator: "/") {
                switch part {
                case ".": continue
                case "..":
                    guard !target.isEmpty else { return nil }
                    target.removeLast()
                default: target.append(String(part))
                }
            }
            let base = new.split(separator: "/").map(String.init)
            let shared = zip(base, target).prefix { $0 == $1 }.count
            let parts = Array(repeating: "..", count: base.count - shared) + target.dropFirst(shared)
            return parts.joined(separator: "/") + path[cut...]
        }
        switch format {
        case .markdown:
            return text.replacing(/(!?\[[^\]\n]*\]\()(<[^>\n]*>|[^)\s]+)/) { m in
                let written = String(m.2)
                let bracketed = written.hasPrefix("<")
                let raw = bracketed ? String(written.dropFirst().dropLast()) : written
                let decoded = raw.removingPercentEncoding ?? raw
                guard let moved = rebase(decoded) else { return String(m.0) }
                // Written encoded, or a space a bare destination can't hold: encoded as the editor writes links.
                let out = bracketed || (raw == decoded && !moved.contains(" "))
                    ? moved : moved.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.union(["#", "?"])) ?? moved
                return "\(m.1)\(bracketed ? "<\(out)>" : out)"
            }
        case .tex:
            return text.replacing(/(\\(?:includegraphics|input|include|includepdf)\*?(?:\[[^\]]*\])?\{)([^}\n]+)\}/) { m in
                rebase(String(m.2)).map { "\(m.1)\($0)}" } ?? String(m.0)
            }
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
