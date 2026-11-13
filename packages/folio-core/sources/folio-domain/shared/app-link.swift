import Foundation

/// The address of anything the app shows: `folio://<kind>/<ID>[#page=N|#^block|#heading|#t=12:30]`, or a place that needs no
/// ID (`folio://today`, `folio://settings/claude`). Every way in (a note's link, the search palette, the sidebar, the CLI, a window's history)
/// names its target with this one value, so there is one place that opens it.
public struct AppLink: Hashable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case today, grades, requirements, people, codes, settings
        /// What each release changed (#415).
        case whatsNew = "whats-new"
        /// What the LMS brought in, waiting to be added or dismissed (#132).
        case proposals
        case semester, course, session, unit, note, material, assignment, exam, card
        case problemSet = "problem-set"
        case person, recording

        /// Where what a link of this kind names is kept, so where it is looked for.
        public enum Home: Sendable {
            /// A page of the app itself, with no ID.
            case app
            /// `transcript.json`: a semester.
            case transcript
            /// `catalog.json`: a person.
            case catalog
            /// A course's `course.json`.
            case course
            /// A unit's quiz file in a course, read only when a link to it is opened.
            case quiz
        }

        // No default in the switches below: a new kind doesn't compile until it says where it lives, what may follow
        // its `#` and whether it has pages, and every switch over these facts (or over the kind) then has to place it.
        public var home: Home {
            switch self {
            case .today, .grades, .requirements, .people, .codes, .settings, .whatsNew, .proposals: .app
            case .semester: .transcript
            case .person: .catalog
            case .course, .session, .unit, .note, .material, .assignment, .exam, .problemSet, .recording: .course
            case .card: .quiz
            }
        }

        public var isPlace: Bool { home == .app }

        /// What may follow `#`: a material's page, a note's block or heading, a recording's moment.
        public var anchors: Set<Anchor.Kind> {
            switch self {
            case .material: [.page]
            case .note: [.block, .heading]
            case .recording: [.time]
            case .today, .grades, .requirements, .people, .codes, .settings, .whatsNew, .proposals, .semester, .person, .course, .session,
                 .unit, .assignment, .exam, .problemSet, .card: []
            }
        }

        /// Whether a path part after it names a page of its own: a course's pages, settings' tabs.
        public var hasPages: Bool {
            switch self {
            case .course, .settings: true
            case .today, .grades, .requirements, .people, .codes, .whatsNew, .proposals, .semester, .person, .session, .unit, .note,
                 .material, .assignment, .exam, .problemSet, .card, .recording: false
            }
        }
    }

    public enum Anchor: Hashable, Sendable {
        /// 1-based, as a PDF viewer counts.
        case page(Int)
        case block(String)
        case heading(String)
        /// Whole seconds into the audio: the address follows playback, and a fraction would make every tick a new link.
        case time(Int)

        public enum Kind: Hashable, Sendable {
            case page, block, heading, time
        }

        public var kind: Kind {
            switch self {
            case .page: .page
            case .block: .block
            case .heading: .heading
            case .time: .time
            }
        }

        var isValid: Bool {
            switch self {
            case .page(let n): n >= 1
            case .block(let b): AppLink.isBlockID(b)
            case .heading(let h): !h.isEmpty
            case .time(let t): t >= 0
            }
        }
    }

    /// A course's own pages. Overview is the course itself and is never written.
    public enum CoursePage: String, CaseIterable, Sendable {
        case overview, sessions, units, notes, materials, quiz, cards, stats, problems, assignments, exams, grades
    }

    /// A tab is a screen of its own, like a course's page, so it is a path and not an anchor: the window's history
    /// compares links without anchors and would take two tabs for one step.
    public enum SettingsPage: String, CaseIterable, Sendable {
        case general, record, classes = "class", notes, review, notifications, claude, lms, backup, about

        /// Tabs before #416 merged or renamed them. Links in patch notes, notes and remembered tabs still name them,
        /// so they are read as the tab that took them over and written by the new name.
        static let formerNames: [String: SettingsPage] = ["profile": .record, "letters": .record, "recording": .classes]

        public init?(rawValue: String) {
            guard let page = Self.allCases.first(where: { $0.rawValue == rawValue }) ?? Self.formerNames[rawValue] else { return nil }
            self = page
        }
    }

    public private(set) var kind: Kind
    public private(set) var id: UUID?
    public private(set) var page: CoursePage?
    /// Nil opens the tab settings showed last.
    public private(set) var settingsPage: SettingsPage?
    public private(set) var anchor: Anchor?

    /// Parts that don't belong to the kind are dropped, so two links to the same thing are equal: a place has no ID,
    /// only a course and settings have pages, and anchors are the kind's own (`Kind.anchors`).
    private init(kind: Kind, id: UUID?, page: CoursePage?, settingsPage: SettingsPage? = nil, anchor: Anchor?) {
        self.kind = kind
        self.id = kind.isPlace ? nil : id
        self.page = kind == .course && page != .overview ? page : nil
        self.settingsPage = kind == .settings ? settingsPage : nil
        self.anchor = anchor.flatMap { kind.anchors.contains($0.kind) && $0.isValid ? $0 : nil }
    }

    public static func place(_ kind: Kind) -> AppLink {
        precondition(kind.isPlace, "\(kind) needs an ID")
        return AppLink(kind: kind, id: nil, page: nil, anchor: nil)
    }

    public static func course(_ id: UUID, page: CoursePage? = nil) -> AppLink {
        AppLink(kind: .course, id: id, page: page, anchor: nil)
    }

    public static func settings(_ page: SettingsPage?) -> AppLink {
        AppLink(kind: .settings, id: nil, page: nil, settingsPage: page, anchor: nil)
    }

    public init(_ kind: Kind, _ id: UUID, anchor: Anchor? = nil) {
        precondition(!kind.isPlace, "\(kind) takes no ID")
        self.init(kind: kind, id: id, page: nil, anchor: anchor)
    }

    /// The same target without its page, block or heading: what a window's history compares.
    public var withoutAnchor: AppLink { with(nil) }

    public func with(_ anchor: Anchor?) -> AppLink { AppLink(kind: kind, id: id, page: page, settingsPage: settingsPage, anchor: anchor) }

    // MARK: Text

    public static let scheme = "folio"

    public var string: String {
        var s = "\(Self.scheme)://\(kind.rawValue)"
        if let id { s += "/\(id.uuidString)" }
        if let page { s += "/\(page.rawValue)" }
        if let settingsPage { s += "/\(settingsPage.rawValue)" }
        switch anchor {
        case .page(let n): s += "#page=\(n)"
        case .block(let b): s += "#^\(b)"
        case .heading(let h): s += "#" + (h.addingPercentEncoding(withAllowedCharacters: Self.headingAllowed) ?? h)
        case .time(let t): s += "#t=" + Self.clock(t)
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
            if kind == .settings, parts.count == 2 {
                guard let tab = SettingsPage(rawValue: parts[1].lowercased()) else { return nil }
                self.init(kind: kind, id: nil, page: nil, settingsPage: tab, anchor: nil)
                return
            }
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
        self.init(kind: kind, id: id, page: page, anchor: Self.anchor(fragment, of: kind))
    }

    /// A note's heading may read `t=1:00`, which the preview hands over raw, so only a kind that takes a moment reads one.
    static func anchor(_ fragment: String, of kind: Kind) -> Anchor? {
        guard !fragment.isEmpty else { return nil }
        if let m = fragment.wholeMatch(of: /page=(\d{1,6})/), let n = Int(m.1) { return .page(n) }
        if kind.anchors.contains(.time), let m = fragment.wholeMatch(of: /t=(?:(\d{1,3}):)?(?:(\d{1,4}):)?(\d{1,6})/) { return time(m.1, m.2, m.3) }
        if fragment.hasPrefix("^") { return .block(String(fragment.dropFirst())) }
        let heading = fragment.removingPercentEncoding ?? fragment
        return heading.isEmpty ? nil : .heading(heading)
    }

    /// `12:30`, `1:02:03`: how a player shows the moment, so the address reads like it.
    public static func clock(_ seconds: Int) -> String {
        seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// `t=750`, `t=12:30` and `t=1:02:03` all name a moment; with one colon the first part is minutes.
    static func time(_ a: Substring?, _ b: Substring?, _ c: Substring) -> Anchor? {
        let parts = [a, b].compactMap { $0 }.compactMap { Int($0) } + [Int(c) ?? 0]
        return .time(parts.reduce(0) { $0 * 60 + $1 })
    }

    /// The `^id` a note writes after a block (`BlockID` in FolioMarkdown).
    static func isBlockID(_ s: String) -> Bool { s.wholeMatch(of: /[A-Za-z0-9-]+/) != nil }

    // MARK: Links in text

    /// `folio://` addresses written in text: a markdown link's target, TeX's `\href{…}`, or a bare address in a
    /// code or text file. Ranges count UTF-16 units, as text views do.
    public static func links(in text: String) -> [(range: NSRange, link: AppLink)] {
        let ns = text as NSString
        return text.matches(of: Self.pattern).compactMap { m in
            let written = trimmed(String(m.0))
            guard let link = AppLink(string: written) else { return nil }
            let range = NSRange(m.range, in: text)
            return (NSRange(location: range.location, length: written.utf16.count), link)
        }
        .filter { $0.range.location != NSNotFound && NSMaxRange($0.range) <= ns.length }
    }

    /// The address under `offset` (UTF-16), for a ⌘-click.
    public static func link(in text: String, at offset: Int) -> AppLink? {
        links(in: text).first { $0.range.location <= offset && offset < NSMaxRange($0.range) }?.link
    }

    /// Ends where a link written in text ends: whitespace, quotes, a closing bracket, or TeX's backslash.
    static var pattern: Regex<Substring> { #/[Ff][Oo][Ll][Ii][Oo]://[^\s<>"'`(){}\[\]\\|]+/# }

    /// Punctuation closing the sentence an address ends is not part of it (`시험은 folio://exam/<ID>#page=12.`), except
    /// in a heading anchor, which may end with it: kept on a page, time or block, it would no longer read as one and
    /// open at the top. A note's preview links a bare address by the same rule (FolioMarkdown's
    /// `HTMLRenderer.linkAddresses`).
    static func trimmed(_ written: String) -> String {
        if let hash = written.firstIndex(of: "#") {
            let anchor = written[written.index(after: hash)...]
            guard anchor.hasPrefix("page=") || anchor.hasPrefix("t=") || anchor.hasPrefix("^") else { return written }
        }
        return String(written.reversed().drop { ".,;:!?".contains($0) }.reversed())
    }
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
    /// reads; for them, and for what no course holds (`Kind.home` other than `.course`), this is nil.
    public func course(in files: [CourseFile]) -> UUID? {
        guard let id else { return nil }
        let holds: (CourseFile) -> Bool
        switch kind {
        case .course: holds = { $0.course.id == id }
        case .session: holds = { $0.sessions.contains { $0.id == id } }
        case .unit: holds = { $0.units.contains { $0.id == id } }
        case .material: holds = { $0.materials.contains { $0.id == id } }
        case .assignment: holds = { $0.assignments.contains { $0.id == id } }
        case .exam: holds = { $0.exams.contains { $0.id == id } }
        case .problemSet: holds = { $0.problemSets.contains { $0.id == id } }
        case .note: holds = { $0.notes.contains { $0.id == id } }
        case .recording: holds = { $0.recordings.contains { $0.id == id } }
        case .today, .grades, .requirements, .people, .codes, .settings, .whatsNew, .proposals, .semester, .person, .card: return nil
        }
        return files.first(where: holds)?.course.id
    }
}

// MARK: Other addresses under the scheme

extension AppLink {
    /// `folio://action/…`: the Claude panel's buttons (copy, apply a proposal), links because its page runs no script.
    /// Never a kind, so a button can't be read as something to open, and a link can't press a button.
    public static let actionHost = "action"

    public static func isAction(_ url: URL) -> Bool {
        url.scheme?.lowercased() == scheme && url.host?.lowercased() == actionHost
    }

    /// `folio://note/<title>`, which a hand-written `[[제목]]` renders to. Not an `AppLink`: a title names a note only
    /// within the course of the note it is written in, so the view showing that note looks it up (`[NoteFile].linked`).
    /// Nil for anything else, an ID link to a note included.
    public static func noteTitle(_ url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme, url.host?.lowercased() == Kind.note.rawValue, AppLink(url: url) == nil else { return nil }
        let title = String(url.path.dropFirst())
        return title.isEmpty ? nil : title
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

/// A tab moved to a window of its own takes its history along.
extension LinkHistory: Codable where Place: Codable {}
