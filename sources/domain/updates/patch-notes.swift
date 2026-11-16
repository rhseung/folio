import Foundation

// PR 본문의 `## 패치 노트` 절과, 릴리스 본문(`releaseBody`, `folio-dev release-notes`)의 같은 제목의 절은 모양이
// 같고, 이 읽기 하나가 둘을 읽는다. 릴리스 본문은 릴리스할 때 PR 본문에서 쓰고 앱은 GitHub에서 릴리스를 다시 읽으므로,
// 머지 뒤에 고친 PR 본문도 릴리스에 들어간다.
public enum PatchNotes {
    public enum Kind: String, CaseIterable, Hashable, Sendable {
        case feat, fix, change

        // UI 문구가 아니라 데이터이다. PR 본문과 릴리스 본문의 모든 줄을 이 값과 맞춘다.
        public var prefix: String { rawValue }
    }

    public struct Item: Hashable, Sendable {
        public var kind: Kind
        public var text: String
        public var link: AppLink?

        public init(kind: Kind, text: String, link: AppLink? = nil) {
            self.kind = kind
            self.text = text
            self.link = link
        }
    }

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
                let a = Int(parts[0]), let b = Int(parts[1]), let c = Int(parts[2]), a >= 0, b >= 0, c >= 0
            else { return nil }
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
    // 릴리스 본문은 제목 아래에 `marker`를 쓴다. 마커가 더 나중의 모양을 가리키는 릴리스는 잘못 읽지 않도록
    // 건너뛴다. 줄의 모양을 바꾸면 `format`을 올린다.
    public static let format = 1
    public static var marker: String { "<!-- folio-patch-notes \(format) -->" }

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

    // `#415 관련`처럼 이슈 번호로 시작하는 줄은 제목이 아니라 글이다.
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

    public static func line(_ item: Item) -> String {
        "- \(item.kind.prefix): \(item.text)" + (item.link.map { " (\($0.string))" } ?? "")
    }

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

    // MARK: Writing the release body

    public struct Merged: Hashable, Sendable {
        public var number: Int
        public var title: String
        public var body: String

        public init(number: Int, title: String, body: String) {
            self.number = number
            self.title = title
            self.body = body
        }
    }

    // 머지된 PR들(번호 차례)의 패치 노트를 종류마다 `### <종류>`로 묶는다. 두 PR이 똑같이 쓴 줄은 한 번만 넣는다.
    public static func releaseBody(_ prs: [Merged], first: Bool) -> String {
        var items: [Item] = []
        for item in prs.flatMap({ Self.items(in: $0.body) }) where !items.contains(item) { items.append(item) }
        let groups = Kind.allCases.compactMap { kind -> String? in
            let lines = items.filter { $0.kind == kind }.map(line)
            return lines.isEmpty ? nil : "### \(kind.prefix)\n" + lines.joined(separator: "\n") + "\n"
        }
        var parts = [
            "## \(heading)\n\(marker)\n" + (groups.isEmpty ? "사용자에게 보이는 변화가 없습니다.\n" : "\n" + groups.joined(separator: "\n"))
        ]
        if first { parts.append("첫 릴리스입니다.\n") }
        if !prs.isEmpty {
            let rows = prs.map { pr in
                let summary = summary(of: pr.body)
                return "- \(pr.title) (#\(pr.number))" + (summary.isEmpty ? "" : "\n  " + summary.prefix(summaryLength))
            }
            parts.append("## 머지된 PR\n" + rows.joined(separator: "\n") + "\n")
        }
        // 앱을 Developer ID로 서명하고 공증하면(#414) 이 안내를 뺀다.
        parts.append(
            "## 설치\n서명과 공증을 하지 않은 빌드입니다. 압축을 풀어 `/Applications`에 옮긴 뒤 처음 한 번 "
                + "`xattr -dr com.apple.quarantine /Applications/Folio.app`을 실행하거나, 시스템 설정 > 개인정보 보호 및 보안에서 "
                + "\"그래도 열기\"를 누릅니다.\n")
        return parts.joined(separator: "\n")
    }

    static let summaryLength = 280

    // PR 본문의 첫 문단이 요약이다. 제목과 세션 링크 문단은 건너뛰고, 굵게와 코드 표시를 떼어 한 줄로 잇는다.
    static func summary(of body: String) -> String {
        let paragraphs = body.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n\n")
        guard
            let first = paragraphs.first(where: {
                let start = $0.drop { $0.isWhitespace }
                return !start.hasPrefix("#") && !start.hasPrefix("https://claude.ai/")
            })
        else { return "" }
        let plain = first.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
        return plain.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: After an update

    public enum Feed: Hashable, Sendable {
        case notLoaded
        case failed
        case loaded([Release])
    }

    public enum Step: Hashable, Sendable {
        case nothing
        case markSeen
        case fetch
        case wait
        case show(Summary)
    }

    public static func step(seen: Version?, current: Version, feed: Feed, busy: Bool) -> Step {
        guard let seen else { return .markSeen }
        guard seen < current else { return .nothing }

        let releases: [Release]
        switch feed {
        case .notLoaded: return .fetch
        case .failed: return .wait
        case .loaded(let all): releases = all
        }

        let unseen = between(releases, after: seen, upTo: current)
        guard unseen.first?.version == current else { return .wait }
        guard unseen.contains(where: \.hasNewFeature) else { return .markSeen }
        if busy { return .wait }
        return summary(unseen, since: seen).map(Step.show) ?? .markSeen
    }

    public static func between(_ releases: [Release], after seen: Version, upTo current: Version) -> [Release] {
        releases.filter { seen < $0.version && $0.version <= current }.sorted { $0.version > $1.version }
    }

    public struct Summary: Hashable, Sendable {
        public var releases: [Release]
        public var since: Version
        public var items: [Item]

        public var latest: Release { releases[0] }
    }

    public static func summary(_ releases: [Release], since: Version) -> Summary? {
        let ordered = releases.sorted { $0.version > $1.version }
        guard !ordered.isEmpty else { return nil }
        return Summary(releases: ordered, since: since, items: Self.ordered(ordered.flatMap(\.items)))
    }

    // MARK: The page

    public static func history(_ releases: [Release], upTo current: Version) -> [Release] {
        releases.filter { $0.version <= current }.sorted { $0.version > $1.version }
    }

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

    public static func ordered(_ items: [Item]) -> [Item] {
        Kind.allCases.flatMap { kind in items.filter { $0.kind == kind } }
    }
}
