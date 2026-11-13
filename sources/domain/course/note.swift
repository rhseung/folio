import Foundation

public enum NoteKind: String, Codable, Sendable, CaseIterable {
    case rough, review
    case examSummary = "exam_summary"
    // 단원 노트는 예전에 주제 노트였다. 파일에는 `topic`으로 적혀 있고, 마이그레이션하지 않고 그대로 읽는다.
    case unit = "topic"
    case free
}

public enum MathSyntax: String, Codable, Sendable, CaseIterable {
    case latex, asciimath
}

public struct NoteMeta: Equatable, Sendable {
    public var id: UUID?
    public var kind: NoteKind
    public var sessionIds: [UUID]
    public var unitIds: [UUID]
    public var examId: UUID?
    public var tags: [String]
    public var math: MathSyntax

    public init(
        id: UUID? = UUID(), kind: NoteKind = .free, sessionId: UUID? = nil, unitIds: [UUID] = [], examId: UUID? = nil, tags: [String] = [],
        math: MathSyntax = .latex
    ) {
        self.id = id
        self.kind = kind
        self.sessionIds = sessionId.map { [$0] } ?? []
        self.unitIds = unitIds
        self.examId = examId
        self.tags = tags
        self.math = math
    }

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
        guard let format = Self.allCases.first(where: { $0.fileExtension == (path as NSString).pathExtension.lowercased() }) else {
            return nil
        }
        self = format
    }
}

public struct NoteEntry: Entity {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var updatedBy: DeviceID

    public var path: String
    public var kind: NoteKind
    public var unitIds: [UUID]
    public var examId: UUID?
    public var tags: [String]
    public var math: MathSyntax
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

    public mutating func apply(_ meta: NoteMeta) {
        kind = meta.kind
        unitIds = meta.kind == .unit ? meta.unitIds : []
        examId = meta.examId
        tags = meta.tags
        math = meta.math
    }
}

extension CourseFile {
    public func meta(of entry: NoteEntry) -> NoteMeta {
        let sessions = sessions(pointingAt: entry.id)
        let units: [UUID] =
            switch entry.kind {
            case .unit: entry.unitIds
            case .rough, .review:
                UnitTree.outline(self.units).map(\.unit).filter { u in sessions.contains { u.sessionIds.contains($0.id) } }.map(\.id)
            case .examSummary: exams.first { $0.id == entry.examId }?.scopeUnitIds ?? []
            case .free: []
            }
        var meta = NoteMeta(id: entry.id, kind: entry.kind, unitIds: units, examId: entry.examId, tags: entry.tags, math: entry.math)
        meta.sessionIds = sessions.map(\.id)
        return meta
    }
}

public enum NoteTemplate {
    public static func defaultSections(for kind: NoteKind) -> [String] {
        switch kind {
        case .rough, .free: []
        case .review: ["이번 회차의 단원", "핵심 정의와 정리", "예시", "모르는 것"]
        case .examSummary: ["시험 범위", "단원별 요약", "자주 틀리는 것", "공식과 정리 모음"]
        case .unit: ["정의", "정리와 증명", "예시와 반례", "관련 단원"]
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

    // 첫 최상위 제목이 아직 `old`일 때만 바꾼다. 사용자가 고쳐 쓴 제목은 사용자의 것이다.
    public static func retitled(_ text: String, from old: String, to new: String, format: NoteFormat) -> String {
        let (heading, replacement) =
            switch format {
            case .markdown: ("# \(old)", "# \(new)")
            case .tex: ("\\section*{\(texEscaped(old))}", "\\section*{\(texEscaped(new))}")
            }
        var lines = text.components(separatedBy: "\n")
        let isTop: (String) -> Bool = format == .markdown ? { $0.hasPrefix("# ") } : { $0.hasPrefix("\\section") }
        guard let i = lines.firstIndex(where: { isTop($0.trimmingCharacters(in: .whitespaces)) }),
            lines[i].trimmingCharacters(in: .whitespaces) == heading
        else { return text }
        lines[i] = replacement
        return lines.joined(separator: "\n")
    }

    // 미리보기와 TeX는 상대 경로를 노트 폴더에서 풀므로, 고치지 않으면 옮길 때마다 그림이 모두 깨진다.
    public static func rebased(_ text: String, from old: String, to new: String, format: NoteFormat) -> String {
        guard old != new else { return text }
        func rebase(_ path: String) -> String? {
            guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("#"), !path.contains("://"),
                path.firstIndex(of: ":").map({ colon in !path[..<colon].contains("/") }) != true
            else { return nil }
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
                let out =
                    bracketed || (raw == decoded && !moved.contains(" "))
                    ? moved : moved.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.union(["#", "?"])) ?? moved
                return "\(m.1)\(bracketed ? "<\(out)>" : out)"
            }
        case .tex:
            return text.replacing(/(\\(?:includegraphics|input|include|includepdf)\*?(?:\[[^\]]*\])?\{)([^}\n]+)\}/) { m in
                rebase(String(m.2)).map { "\(m.1)\($0)}" } ?? String(m.0)
            }
        }
    }

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

public enum Note {
    public typealias ID = UUID
    public typealias Path = String
}
