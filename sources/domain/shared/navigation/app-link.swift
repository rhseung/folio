import Foundation

public struct AppLink: Hashable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case today, grades, requirements, people, codes, settings
        case whatsNew = "whats-new"
        case proposals
        case semester, course, session, unit, note, material, assignment, exam, card
        case problemSet = "problem-set"
        case person, recording

        public enum Home: Sendable {
            case app
            case transcript
            case catalog
            case course
            case quiz
        }

        // 아래 switch에는 default를 두지 않는다. 그래야 새 종류는 어디에 있는지, `#` 뒤에 무엇이 오는지, 페이지가
        // 있는지를 정할 때까지 컴파일되지 않고, 이 값들(또는 종류)을 가르는 모든 switch가 새 종류를 다루게 된다.
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

        public var anchors: Set<Anchor.Kind> {
            switch self {
            case .material: [.page]
            case .note: [.block, .heading]
            case .recording: [.time]
            case .today, .grades, .requirements, .people, .codes, .settings, .whatsNew, .proposals, .semester, .person, .course, .session,
                .unit, .assignment, .exam, .problemSet, .card:
                []
            }
        }

        public var hasPages: Bool {
            switch self {
            case .course, .settings: true
            case .today, .grades, .requirements, .people, .codes, .whatsNew, .proposals, .semester, .person, .session, .unit, .note,
                .material, .assignment, .exam, .problemSet, .card, .recording:
                false
            }
        }
    }

    public enum Anchor: Hashable, Sendable {
        case page(Int)
        case block(String)
        case heading(String)
        // 주소가 재생 위치를 따라가므로, 소수를 쓰면 틱마다 새 링크가 생긴다. 그래서 초 단위 정수로 둔다.
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

    public enum CoursePage: String, CaseIterable, Sendable {
        case overview, sessions, units, notes, materials, quiz, cards, stats, problems, assignments, exams, grades
    }

    // 창의 기록은 앵커를 빼고 링크를 비교하므로, 탭을 앵커로 두면 두 탭을 한 걸음으로 본다. 그래서 탭은 과목의
    // 페이지처럼 경로로 둔다.
    public enum SettingsPage: String, CaseIterable, Sendable {
        case general, record, classes = "class", notes, review, notifications, claude, lms, backup, about

        // 합치거나 이름을 바꾸기 전의 탭 이름이다. 패치 노트, 노트, 기억한 탭의 링크가 아직 이 이름을 쓰므로, 이어받은
        // 탭으로 읽고 새 이름으로 쓴다.
        static let formerNames: [String: SettingsPage] = ["profile": .record, "letters": .record, "recording": .classes]

        public init?(rawValue: String) {
            guard let page = Self.allCases.first(where: { $0.rawValue == rawValue }) ?? Self.formerNames[rawValue] else { return nil }
            self = page
        }
    }

    public private(set) var kind: Kind
    public private(set) var id: UUID?
    public private(set) var page: CoursePage?
    public private(set) var settingsPage: SettingsPage?
    public private(set) var anchor: Anchor?

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

    // 예약되지 않은 ASCII만 그대로 두고 나머지는 모두 이스케이프한다. 그래야 링크가 글 속 링크가 끝나는 자리(공백,
    // `)`, `}`, `]`, 따옴표)에서 끝나고, 제목이 블록(`^`)이나 쪽(`=`)으로 읽히지 않으며, 복사한 링크를 마크다운,
    // TeX, 일반 텍스트에 붙여도 바뀌지 않는다.
    static let headingAllowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    // Foundation은 URL을 만들 때 블록의 `^`를 이스케이프하므로, URL에서 `%5E` 뒤에 블록 ID가 오면 블록이다. URL에서
    // `^`로 시작하는 제목은 블록으로 읽는다. 이 링크가 따르는 Obsidian에는 그런 제목이 없다.
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

    // `URLComponents`는 노트의 위키 링크가 미리보기에 넣는 대로 공백이나 한글이 든 날 제목을 거절하므로, 손으로 읽는다.
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

    // 미리보기는 노트 제목 `t=1:00`을 그대로 넘기므로, 재생 위치를 받는 종류만 이 값을 읽는다.
    static func anchor(_ fragment: String, of kind: Kind) -> Anchor? {
        guard !fragment.isEmpty else { return nil }
        if let m = fragment.wholeMatch(of: /page=(\d{1,6})/), let n = Int(m.1) { return .page(n) }
        if kind.anchors.contains(.time), let m = fragment.wholeMatch(of: /t=(?:(\d{1,3}):)?(?:(\d{1,4}):)?(\d{1,6})/) {
            return time(m.1, m.2, m.3)
        }
        if fragment.hasPrefix("^") { return .block(String(fragment.dropFirst())) }
        let heading = fragment.removingPercentEncoding ?? fragment
        return heading.isEmpty ? nil : .heading(heading)
    }

    public static func clock(_ seconds: Int) -> String {
        seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    static func time(_ a: Substring?, _ b: Substring?, _ c: Substring) -> Anchor? {
        let parts = [a, b].compactMap { $0 }.compactMap { Int($0) } + [Int(c) ?? 0]
        return .time(parts.reduce(0) { $0 * 60 + $1 })
    }

    static func isBlockID(_ s: String) -> Bool { s.wholeMatch(of: /[A-Za-z0-9-]+/) != nil }

    // MARK: Links in text

    // 범위는 텍스트 뷰처럼 UTF-16 단위로 센다.
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

    public static func link(in text: String, at offset: Int) -> AppLink? {
        links(in: text).first { $0.range.location <= offset && offset < NSMaxRange($0.range) }?.link
    }

    static var pattern: Regex<Substring> { #/[Ff][Oo][Ll][Ii][Oo]://[^\s<>"'`(){}\[\]\\|]+/# }

    // 주소가 끝나는 문장의 문장부호(`시험은 folio://exam/<ID>#page=12.`)는 주소에 넣지 않는다. 제목 앵커는 문장부호로
    // 끝날 수 있으므로 예외이다. 쪽, 시각, 블록에 문장부호를 남기면 그 앵커로 읽히지 않아 맨 위에서 열린다. 노트
    // 미리보기도 같은 규칙으로 맨 주소를 링크로 만든다(FolioMarkdown의 `HTMLRenderer.linkAddresses`).
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
    public init(_ item: SearchItem) {
        let kind: Kind =
            switch item.kind {
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
    // 패널 페이지는 스크립트를 실행하지 않으므로 Claude 패널의 버튼(복사, 제안 적용)은 링크이다. 버튼이 열 대상으로
    // 읽히거나 링크가 버튼을 누르지 않도록, 이 이름은 종류가 되지 않는다.
    public static let actionHost = "action"

    public static func isAction(_ url: URL) -> Bool {
        url.scheme?.lowercased() == scheme && url.host?.lowercased() == actionHost
    }

    public static func noteTitle(_ url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme, url.host?.lowercased() == Kind.note.rawValue, AppLink(url: url) == nil else { return nil }
        let title = String(url.path.dropFirst())
        return title.isEmpty ? nil : title
    }
}

public struct LinkHistory<Place: Equatable & Sendable>: Equatable, Sendable {
    public private(set) var back: [Place] = []
    public private(set) var current: Place
    public private(set) var forward: [Place] = []
    public let limit: Int

    public init(_ current: Place, limit: Int = 100) {
        self.current = current
        self.limit = max(1, limit)
    }

    public var canGoBack: Bool { !back.isEmpty }
    public var canGoForward: Bool { !forward.isEmpty }

    public mutating func visit(_ place: Place) {
        guard place != current else { return }
        back.append(current)
        if back.count > limit { back.removeFirst(back.count - limit) }
        forward = []
        current = place
    }

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

extension LinkHistory: Codable where Place: Codable {}
