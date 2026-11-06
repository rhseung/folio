import Foundation

/// The address of anything the app shows: `folio://<kind>/<ID>[#page=N|#^block|#heading]`, or a place that needs no
/// ID (`folio://today`). Every way in (a note's link, the search palette, the sidebar, the CLI, a window's history)
/// names its target with this one value, so there is one place that opens it.
public struct AppLink: Hashable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case today, grades, requirements, people, codes, settings
        case semester, course, session, unit, note, material, assignment, exam, card
        case problemSet = "problem-set"
        case person

        /// A page of the app itself, with no ID.
        public var isPlace: Bool {
            switch self {
            case .today, .grades, .requirements, .people, .codes, .settings: true
            default: false
            }
        }
    }

    public enum Anchor: Hashable, Sendable {
        /// 1-based, as a PDF viewer counts.
        case page(Int)
        case block(String)
        case heading(String)
    }

    /// A course's own pages. Overview is the course itself and is never written.
    public enum CoursePage: String, CaseIterable, Sendable {
        case overview, sessions, units, notes, materials, quiz, cards, stats, problems, assignments, exams, grades
    }

    public private(set) var kind: Kind
    public private(set) var id: UUID?
    public private(set) var page: CoursePage?
    public private(set) var anchor: Anchor?

    /// Parts that don't belong to the kind are dropped, so two links to the same thing are equal: a place has no ID,
    /// only a course has pages, only a material has page numbers and only a note has blocks and headings.
    private init(kind: Kind, id: UUID?, page: CoursePage?, anchor: Anchor?) {
        self.kind = kind
        self.id = kind.isPlace ? nil : id
        self.page = kind == .course && page != .overview ? page : nil
        self.anchor = switch anchor {
        case .page(let n) where kind == .material && n >= 1: anchor
        case .block(let b) where kind == .note && Self.isBlockID(b): anchor
        case .heading(let h) where kind == .note && !h.isEmpty: anchor
        default: nil
        }
    }

    public static func place(_ kind: Kind) -> AppLink {
        precondition(kind.isPlace, "\(kind) needs an ID")
        return AppLink(kind: kind, id: nil, page: nil, anchor: nil)
    }

    public static func course(_ id: UUID, page: CoursePage? = nil) -> AppLink {
        AppLink(kind: .course, id: id, page: page, anchor: nil)
    }

    public init(_ kind: Kind, _ id: UUID, anchor: Anchor? = nil) {
        precondition(!kind.isPlace, "\(kind) takes no ID")
        self.init(kind: kind, id: id, page: nil, anchor: anchor)
    }

    /// The same target without its page, block or heading: what a window's history compares.
    public var withoutAnchor: AppLink { AppLink(kind: kind, id: id, page: page, anchor: nil) }

    public func with(_ anchor: Anchor?) -> AppLink { AppLink(kind: kind, id: id, page: page, anchor: anchor) }

    // MARK: Text

    public static let scheme = "folio"

    public var string: String {
        var s = "\(Self.scheme)://\(kind.rawValue)"
        if let id { s += "/\(id.uuidString)" }
        if let page { s += "/\(page.rawValue)" }
        switch anchor {
        case .page(let n): s += "#page=\(n)"
        case .block(let b): s += "#^\(b)"
        case .heading(let h): s += "#" + (h.addingPercentEncoding(withAllowedCharacters: Self.headingAllowed) ?? h)
        case nil: break
        }
        return s
    }

    public var url: URL { URL(string: string)! }

    /// Only unreserved ASCII stays as is. Everything else is escaped, so a link ends where links in text end (space,
    /// `)`, `}`, `]`, quotes), a heading can't be read as a block (`^`) or a page (`=`), and a copied link pastes
    /// unchanged into markdown, TeX and plain text.
    static let headingAllowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    /// Foundation escapes the `^` of a block when it makes the URL, so there `%5E` followed by a block ID is a block.
    /// A heading that starts with `^` reads as a block from a URL; Obsidian, whose links these follow, has none.
    public init?(url: URL) {
        var string = url.absoluteString
        if let hash = string.firstIndex(of: "#") {
            let fragment = string[string.index(after: hash)...]
            if fragment.prefix(3).uppercased() == "%5E", Self.isBlockID(String(fragment.dropFirst(3))) {
                string = string[...hash] + "^" + fragment.dropFirst(3)
            }
        }
        self.init(string: string)
    }

    /// Read by hand rather than through `URLComponents`, which refuses a raw heading with spaces or Hangul, the way
    /// a note's wiki link puts it into the preview.
    public init?(string: String) {
        let prefix = "\(Self.scheme)://"
        guard string.count > prefix.count, string.prefix(prefix.count).lowercased() == prefix else { return nil }
        let rest = string.dropFirst(prefix.count)
        let hash = rest.firstIndex(of: "#")
        var parts = rest[..<(hash ?? rest.endIndex)].split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if parts.count > 1, parts.last == "" { parts.removeLast() }
        guard let first = parts.first, let kind = Kind(rawValue: first.lowercased()) else { return nil }
        let fragment = hash.map { String(rest[rest.index(after: $0)...]) } ?? ""
        if kind.isPlace {
            guard parts.count == 1 else { return nil }
            self.init(kind: kind, id: nil, page: nil, anchor: nil)
            return
        }
        guard parts.count >= 2, let id = UUID(uuidString: parts[1]) else { return nil }
        var page: CoursePage?
        if parts.count == 3, kind == .course {
            guard let p = CoursePage(rawValue: parts[2].lowercased()) else { return nil }
            page = p
        } else if parts.count != 2 {
            return nil
        }
        self.init(kind: kind, id: id, page: page, anchor: Self.anchor(fragment))
    }

    static func anchor(_ fragment: String) -> Anchor? {
        guard !fragment.isEmpty else { return nil }
        if let m = fragment.wholeMatch(of: /page=(\d{1,6})/), let n = Int(m.1) { return .page(n) }
        if fragment.hasPrefix("^") { return .block(String(fragment.dropFirst())) }
        let heading = fragment.removingPercentEncoding ?? fragment
        return heading.isEmpty ? nil : .heading(heading)
    }

    /// The `^id` a note writes after a block (`BlockID` in FolioMarkdown).
    static func isBlockID(_ s: String) -> Bool { s.wholeMatch(of: /[A-Za-z0-9-]+/) != nil }

    // MARK: Links in text

    /// `folio://` addresses written in text: a markdown link's target, TeX's `\href{…}`, or a bare address in a
    /// code or text file. Ranges count UTF-16 units, as text views do.
    public static func links(in text: String) -> [(range: NSRange, link: AppLink)] {
        let ns = text as NSString
        return text.matches(of: Self.pattern).compactMap { m in
            guard let link = AppLink(string: String(m.0)) else { return nil }
            return (NSRange(m.range, in: text), link)
        }
        .filter { $0.range.location != NSNotFound && NSMaxRange($0.range) <= ns.length }
    }

    /// The address under `offset` (UTF-16), for a ⌘-click.
    public static func link(in text: String, at offset: Int) -> AppLink? {
        links(in: text).first { $0.range.location <= offset && offset < NSMaxRange($0.range) }?.link
    }

    /// Ends where a link written in text ends: whitespace, quotes, a closing bracket, or TeX's backslash.
    static var pattern: Regex<Substring> { #/[Ff][Oo][Ll][Ii][Oo]://[^\s<>"'`(){}\[\]\\|]+/# }
}

extension AppLink: Codable {
    public init(from decoder: any Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let link = AppLink(string: s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a folio:// link: \(s)"))
        }
        self = link
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(string)
    }
}

extension AppLink: CustomStringConvertible {
    public var description: String { string }
}

extension AppLink {
    /// Where a search result opens.
    public init(_ item: SearchItem) {
        let kind: Kind = switch item.kind {
        case .note: .note
        case .material: .material
        case .assignment: .assignment
        case .exam: .exam
        case .session: .session
        case .unit: .unit
        case .quiz: .card
        }
        self.init(kind, item.id)
    }

    /// The course whose `course.json` holds the target. Cards live in quiz files of their own, which the caller
    /// reads; for them, and for what no course holds, this is nil.
    public func course(in files: [CourseFile]) -> UUID? {
        guard let id else { return nil }
        let holds: (CourseFile) -> Bool = switch kind {
        case .course: { $0.course.id == id }
        case .session: { $0.sessions.contains { $0.id == id } }
        case .unit: { $0.units.contains { $0.id == id } }
        case .material: { $0.materials.contains { $0.id == id } }
        case .assignment: { $0.assignments.contains { $0.id == id } }
        case .exam: { $0.exams.contains { $0.id == id } }
        case .problemSet: { $0.problemSets.contains { $0.id == id } }
        case .note: { $0.notes.contains { $0.id == id } }
        default: { _ in false }
        }
        return files.first(where: holds)?.course.id
    }
}

/// Where a window (or later a pane) has been, for back and forward. Only moves between screens go in; changing data
/// is undone by the actions, not here.
public struct LinkHistory<Place: Equatable & Sendable>: Equatable, Sendable {
    /// Oldest first.
    public private(set) var back: [Place] = []
    public private(set) var current: Place
    /// Nearest first.
    public private(set) var forward: [Place] = []
    public let limit: Int

    public init(_ current: Place, limit: Int = 100) {
        self.current = current
        self.limit = max(1, limit)
    }

    public var canGoBack: Bool { !back.isEmpty }
    public var canGoForward: Bool { !forward.isEmpty }

    /// A new place drops what was ahead, as in a browser. The same place again adds nothing.
    public mutating func visit(_ place: Place) {
        guard place != current else { return }
        back.append(current)
        if back.count > limit { back.removeFirst(back.count - limit) }
        forward = []
        current = place
    }

    /// The same screen showing something else of its own (a PDF scrolled to another page): no new step.
    public mutating func replace(_ place: Place) {
        current = place
    }

    @discardableResult
    public mutating func goBack(_ steps: Int = 1) -> Bool {
        guard steps >= 1, steps <= back.count else { return false }
        for _ in 0..<steps {
            forward.insert(current, at: 0)
            current = back.removeLast()
        }
        return true
    }

    @discardableResult
    public mutating func goForward(_ steps: Int = 1) -> Bool {
        guard steps >= 1, steps <= forward.count else { return false }
        for _ in 0..<steps {
            back.append(current)
            current = forward.removeFirst()
        }
        return true
    }
}
