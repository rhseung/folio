import Foundation

/// What each release changed, as the app shows it after an update (#415).
///
/// One shape is written in two places and read by one reader: a PR's body carries a `## 패치 노트` section of item lines
/// (`- feat: …`, `- fix: …`, `- change: …`, each optionally ending in a `(folio://…)` link), and the release script
/// (`scripts/release-notes.sh`) copies the merged PRs' lines into the GitHub release's body under the same heading, in
/// `### feat`-style groups. The app reads the releases back from GitHub, so a PR body edited after its merge still
/// reaches the release.
public enum PatchNotes {
    /// Named as commits are, in English and untranslated (2026-11-10 사용자). In the order a release lists them.
    public enum Kind: String, CaseIterable, Hashable, Sendable {
        case feat, fix, change

        /// What a line starts with. Data rather than UI copy: every line is matched against it, and the release script
        /// matches the same words.
        public var prefix: String { rawValue }
    }

    public struct Item: Hashable, Sendable {
        public var kind: Kind
        public var text: String
        /// Only a place of the app (`AppLink.Kind.isPlace`, a settings tab included): an item is read by everyone, and
        /// a note or a course is somebody's own.
        public var link: AppLink?

        public init(kind: Kind, text: String, link: AppLink? = nil) {
            self.kind = kind
            self.text = text
            self.link = link
        }
    }

    /// `major.minor.patch`, as `FolioVersion` writes it and a release tag carries it (`v0.3.0`).
    public struct Version: Hashable, Comparable, Sendable, CustomStringConvertible {
        public var major: Int
        public var minor: Int
        public var patch: Int

        public init(_ major: Int, _ minor: Int, _ patch: Int) {
            self.major = major
            self.minor = minor
            self.patch = patch
        }

        public init?(_ text: String) {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            let bare = trimmed.first == "v" || trimmed.first == "V" ? trimmed.dropFirst() : Substring(trimmed)
            let parts = bare.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) }),
                  let a = Int(parts[0]), let b = Int(parts[1]), let c = Int(parts[2]), a >= 0, b >= 0, c >= 0 else { return nil }
            self.init(a, b, c)
        }

        public static func < (a: Version, b: Version) -> Bool {
            (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)
        }

        public var description: String { "\(major).\(minor).\(patch)" }
    }

    public struct Release: Hashable, Sendable {
        public var version: Version
        public var date: Date?
        public var items: [Item]

        public init(version: Version, date: Date? = nil, items: [Item]) {
            self.version = version
            self.date = date
            self.items = items
        }

        public var hasNewFeature: Bool { items.contains { $0.kind == .feat } }
    }

    // MARK: Reading the text

    public static let heading = "패치 노트"
    /// The shape of the item lines. The release script writes `marker` under the heading; a release whose marker
    /// names a later shape is skipped rather than misread.
    public static let format = 1
    public static var marker: String { "<!-- folio-patch-notes \(format) -->" }

    /// The items of the `## 패치 노트` section of a PR's or a release's body, in the order written. Lines that are not
    /// items (prose, a blank line, the marker, a release's `### feat` group headings) are passed over; the section ends
    /// at the next heading of its level or above.
    public static func items(in body: String) -> [Item] {
        var inSection = false
        var items: [Item] = []
        for raw in body.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let level = headingLevel(line) {
                if inSection, level <= 2 { break }
                if !inSection { inSection = isHeading(line) }
                continue
            }
            guard inSection else { continue }
            if let shape = markerFormat(line), shape > format { return [] }
            if let found = item(line) { items.append(found) }
        }
        return items
    }

    /// A markdown heading's level: `#`s and a space. A line opening with an issue number (`#415 관련`) is text.
    static func headingLevel(_ line: String) -> Int? {
        guard let m = line.wholeMatch(of: /([#]{1,6})(\s.*)?/) else { return nil }
        return m.1.count
    }

    static func isHeading(_ line: String) -> Bool {
        guard line.hasPrefix("## ") else { return false }
        return line.dropFirst(3).trimmingCharacters(in: .whitespaces) == heading
    }

    static func markerFormat(_ line: String) -> Int? {
        guard let m = line.wholeMatch(of: /<!--\s*folio-patch-notes\s+(\d+)\s*-->/) else { return nil }
        return Int(m.1)
    }

    /// `- feat: 노트 목차 (folio://settings/notes)`. A link that is not a place is dropped and its text with it, so
    /// the line still reads as a sentence.
    public static func item(_ line: String) -> Item? {
        var rest = Substring(line.trimmingCharacters(in: .whitespaces))
        guard let bullet = rest.first, bullet == "-" || bullet == "*" else { return nil }
        rest = rest.dropFirst().drop { $0 == " " || $0 == "\t" }
        guard let kind = Kind.allCases.first(where: { rest.hasPrefix($0.prefix) }) else { return nil }
        rest = rest.dropFirst(kind.prefix.count).drop { $0 == " " }
        guard rest.first == ":" else { return nil }
        var text = rest.dropFirst().trimmingCharacters(in: .whitespaces)

        var link: AppLink?
        if text.hasSuffix(")"), let open = text.range(of: "(\(AppLink.scheme)://", options: .backwards) {
            let address = String(text[text.index(after: open.lowerBound)..<text.index(before: text.endIndex)])
            if !address.contains(where: \.isWhitespace) {
                link = AppLink(string: address).flatMap { $0.kind.isPlace ? $0 : nil }
                text = text[..<open.lowerBound].trimmingCharacters(in: .whitespaces)
            }
        }

        guard !text.isEmpty else { return nil }
        return Item(kind: kind, text: text, link: link)
    }

    /// The line `item(_:)` reads back.
    public static func line(_ item: Item) -> String {
        "- \(item.kind.prefix): \(item.text)" + (item.link.map { " (\($0.string))" } ?? "")
    }

    /// GitHub's list of releases (`GET /repos/{owner}/{repo}/releases`), newest first. Drafts and prereleases are
    /// left out, as is a release whose tag is no version.
    public static func releases(fromGitHub data: Data) throws -> [Release] {
        struct Raw: Decodable {
            var tagName: String
            var body: String?
            var draft: Bool?
            var prerelease: Bool?
            var publishedAt: String?

            enum CodingKeys: String, CodingKey {
                case tagName = "tag_name", body, draft, prerelease, publishedAt = "published_at"
            }
        }

        let raws = try JSONDecoder().decode([Raw].self, from: data)
        return raws.compactMap { raw -> Release? in
            guard raw.draft != true, raw.prerelease != true, let version = Version(raw.tagName) else { return nil }
            let date = raw.publishedAt.flatMap { try? Date($0, strategy: .iso8601) }
            return Release(version: version, date: date, items: items(in: raw.body ?? ""))
        }
        .sorted { $0.version > $1.version }
    }

    // MARK: After an update

    /// What came of asking GitHub for the releases.
    public enum Feed: Hashable, Sendable {
        case notLoaded
        case failed
        case loaded([Release])
    }

    /// What the app does about the notes at launch and as the minute turns.
    public enum Step: Hashable, Sendable {
        /// Nothing new since the last look (or an older app opened after a newer one).
        case nothing
        /// The first launch, or an update without a new feature: remembered as seen, nothing shown.
        case markSeen
        case fetch
        /// Not now: GitHub failed (next launch), the release isn't published yet, or a class or a recording is under way.
        case wait
        case show(Summary)
    }

    /// `seen` is the version this device last looked at, nil before the first launch with the notes. Only a version
    /// with a new feature shows the sheet; several versions skipped at once show one.
    public static func step(seen: Version?, current: Version, feed: Feed, busy: Bool) -> Step {
        // A first install has nothing to compare against: all of it is new.
        guard let seen else { return .markSeen }
        guard seen < current else { return .nothing }

        let releases: [Release]
        switch feed {
        case .notLoaded: return .fetch
        case .failed: return .wait
        case .loaded(let all): releases = all
        }

        let unseen = between(releases, after: seen, upTo: current)
        // Until the running version's release is published (a draft is skipped), its notes aren't known yet.
        guard unseen.first?.version == current else { return .wait }
        guard unseen.contains(where: \.hasNewFeature) else { return .markSeen }
        if busy { return .wait }
        return summary(unseen, since: seen).map(Step.show) ?? .markSeen
    }

    public static func between(_ releases: [Release], after seen: Version, upTo current: Version) -> [Release] {
        releases.filter { seen < $0.version && $0.version <= current }.sorted { $0.version > $1.version }
    }

    /// One sheet for the versions an update brought, however many were skipped.
    public struct Summary: Hashable, Sendable {
        /// Newest first, never empty.
        public var releases: [Release]
        public var since: Version
        /// Every item of those versions, as one list the way the page lists a version: kind by kind, each kind's newest
        /// version first.
        public var items: [Item]

        public var latest: Release { releases[0] }
    }

    public static func summary(_ releases: [Release], since: Version) -> Summary? {
        let ordered = releases.sorted { $0.version > $1.version }
        guard !ordered.isEmpty else { return nil }
        return Summary(releases: ordered, since: since, items: Self.ordered(ordered.flatMap(\.items)))
    }

    // MARK: The page

    /// Every release up to `current`, newest first: a later one is for an app not yet installed.
    public static func history(_ releases: [Release], upTo current: Version) -> [Release] {
        releases.filter { $0.version <= current }.sorted { $0.version > $1.version }
    }

    /// The releases with the items of `kind` (any, when nil) whose text has `query`; a release left with none is left out.
    public static func filter(_ releases: [Release], kind: Kind?, query: String) -> [Release] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
        return releases.compactMap { release in
            var r = release
            r.items = release.items.filter { item in
                (kind == nil || item.kind == kind) && (q.isEmpty || item.text.range(of: q, options: options) != nil)
            }
            return r.items.isEmpty ? nil : r
        }
    }

    /// A release's items in one list, kind by kind in `Kind` order, each kind in the order written.
    public static func ordered(_ items: [Item]) -> [Item] {
        Kind.allCases.flatMap { kind in items.filter { $0.kind == kind } }
    }
}
