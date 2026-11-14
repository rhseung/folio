import Foundation

public struct LMSClassroom: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var title: String
    public var kind: String?
    public var professors: String?

    public init(id: Int, title: String, kind: String? = nil, professors: String? = nil) {
        self.id = id
        self.title = title
        self.kind = kind
        self.professors = professors
    }

    public var url: URL { LMS.url("/course/view.php?id=\(id)") }
}

public struct LMSAssignment: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var classroom: Int
    public var title: String
    public var due: Date?
    public var submitted: Bool

    public init(id: Int, classroom: Int, title: String, due: Date? = nil, submitted: Bool = false) {
        self.id = id
        self.classroom = classroom
        self.title = title
        self.due = due
        self.submitted = submitted
    }

    public var key: LMSKey { .init(kind: .assignment, id: id) }
    public var url: URL { LMS.url("/mod/assign/view.php?id=\(id)") }
}

// 받을 수 있는 파일인지는 페이지를 열어야 안다. 허용된 파일은 원본으로 리디렉션되고, 나머지는 Coursemos
// 뷰어만 보이므로 링크로 남긴다.
public struct LMSFile: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var classroom: Int
    public var title: String
    public var week: String?

    public init(id: Int, classroom: Int, title: String, week: String? = nil) {
        self.id = id
        self.classroom = classroom
        self.title = title
        self.week = week
    }

    public var key: LMSKey { .init(kind: .file, id: id) }
    public var url: URL { LMS.url("/mod/ubfile/view.php?id=\(id)") }

    public func lectureName(_ downloaded: String) -> String {
        guard downloaded.first?.isNumber == false, let week, let number = Int(week.prefix { $0.isNumber }) else { return downloaded }
        return String(format: "%02d_", number) + downloaded
    }
}

public struct LMSNotice: Codable, Hashable, Sendable, Identifiable {
    // `bwid`는 게시판 전체에서 겹치지 않는다.
    public var id: Int
    public var board: Int
    public var classroom: Int
    public var title: String
    public var author: String?
    public var posted: Date?

    public init(id: Int, board: Int, classroom: Int, title: String, author: String? = nil, posted: Date? = nil) {
        self.id = id
        self.board = board
        self.classroom = classroom
        self.title = title
        self.author = author
        self.posted = posted
    }

    public var key: LMSKey { .init(kind: .notice, id: id) }
    public var url: URL { LMS.url("/mod/ubboard/article.php?id=\(board)&bwid=\(id)") }
}

public struct LMSSnapshot: Codable, Hashable, Sendable {
    public var at: Date
    public var classrooms: [LMSClassroom]
    public var assignments: [LMSAssignment]
    public var files: [LMSFile]
    public var notices: [LMSNotice]

    public init(
        at: Date, classrooms: [LMSClassroom] = [], assignments: [LMSAssignment] = [], files: [LMSFile] = [],
        notices: [LMSNotice] = []
    ) {
        self.at = at
        self.classrooms = classrooms
        self.assignments = assignments
        self.files = files
        self.notices = notices
    }

    public func current(in classroom: Int) -> [LMSKey] {
        files.filter { $0.classroom == classroom }.map(\.key) + notices.filter { $0.classroom == classroom }.map(\.key)
    }

    public mutating func merge(_ other: LMSSnapshot, in classroom: Int) {
        assignments.removeAll { $0.classroom == classroom }
        files.removeAll { $0.classroom == classroom }
        notices.removeAll { $0.classroom == classroom }
        assignments += other.assignments.filter { $0.classroom == classroom }
        files += other.files.filter { $0.classroom == classroom }
        notices += other.notices.filter { $0.classroom == classroom }
    }
}

public struct LMSKey: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    public enum Kind: String, Sendable, CaseIterable {
        case assignment, file, notice
    }

    public var kind: Kind
    public var id: Int

    public init(kind: Kind, id: Int) {
        self.kind = kind
        self.id = id
    }

    public init?(_ text: String) {
        let parts = text.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, let kind = Kind(rawValue: String(parts[0])), let id = Int(parts[1]) else { return nil }
        self.init(kind: kind, id: id)
    }

    public var description: String { "\(kind.rawValue):\(id)" }

    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let key = LMSKey(text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not an LMS key: \(text)"))
        }
        self = key
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }

    public static func < (a: LMSKey, b: LMSKey) -> Bool { (a.kind.rawValue, a.id) < (b.kind.rawValue, b.id) }
}

public struct LMSSettings: Codable, Sendable, Equatable {
    public var known: [Int]
    public var handled: [LMSKey]

    public init(known: [Int] = [], handled: [LMSKey] = []) {
        self.known = known
        self.handled = handled
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        known = try c.decodeIfPresent([Int].self, forKey: .known) ?? []
        handled = try c.decodeIfPresent([LMSKey].self, forKey: .handled) ?? []
    }

    // 두 기기가 같은 일을 하면 같은 파일을 쓰도록, 두 목록은 정렬하고 중복 없이 둔다.
    public mutating func know(_ classrooms: [Int]) {
        known = Set(known).union(classrooms).sorted()
    }

    public mutating func mark(_ keys: [LMSKey], handled on: Bool) {
        var set = Set(handled)
        if on { set.formUnion(keys) } else { set.subtract(keys) }
        handled = set.sorted()
    }

    public func unseen(in snapshot: LMSSnapshot) -> [LMSClassroom] {
        let known = Set(known)
        return snapshot.classrooms.filter { !known.contains($0.id) }
    }
}

public enum LMS {
    public static let base = URL(string: "https://lms.gist.ac.kr")!
    // LMS 페이지의 날짜는 시간대를 적지 않은 한국 시각이다.
    public static let timeZone = TimeZone(identifier: "Asia/Seoul")!

    public static func url(_ path: String) -> URL { URL(string: path, relativeTo: base)!.absoluteURL }
}

public struct LMSProposal: Hashable, Sendable, Identifiable {
    public enum Item: Hashable, Sendable {
        case assignment(LMSAssignment)
        case file(LMSFile)
        case notice(LMSNotice)
    }

    public var item: Item
    public var classroom: LMSClassroom

    public init(item: Item, classroom: LMSClassroom) {
        self.item = item
        self.classroom = classroom
    }

    public var key: LMSKey {
        switch item {
        case .assignment(let a): a.key
        case .file(let f): f.key
        case .notice(let n): n.key
        }
    }

    public var id: String { key.description }

    public var title: String {
        switch item {
        case .assignment(let a): a.title
        case .file(let f): f.title
        case .notice(let n): n.title
        }
    }

    public var url: URL {
        switch item {
        case .assignment(let a): a.url
        case .file(let f): f.url
        case .notice(let n): n.url
        }
    }
}

public struct LMSInbox: Sendable, Equatable {
    public struct Handled: Sendable, Equatable, Identifiable {
        public var proposal: LMSProposal
        public var course: UUID?
        // 과목에 이미 있거나, 제출했거나, 마감이 지난 과제는 `build`가 제안에서 빼므로, 표시를 거두면 화면에서 아예
        // 사라진다. 그래서 이런 과제는 false이다.
        public var proposable: Bool
        public var id: String { proposal.id }
    }

    public struct Section: Sendable, Equatable, Identifiable {
        public var classroom: LMSClassroom
        public var proposals: [LMSProposal]
        public var handled: [Handled]
        public var id: Int { classroom.id }

        public init(classroom: LMSClassroom, proposals: [LMSProposal], handled: [Handled] = []) {
            self.classroom = classroom
            self.proposals = proposals
            self.handled = handled
        }
    }

    public var sections: [Section]

    public init(sections: [Section] = []) { self.sections = sections }

    public var proposals: [LMSProposal] { sections.flatMap(\.proposals) }
    public var waiting: [Section] { sections.filter { !$0.proposals.isEmpty } }
    public var isEmpty: Bool { proposals.isEmpty }

    public static func build(_ snapshot: LMSSnapshot, settings: LMSSettings, courses: [CourseFile], now: Date) -> LMSInbox {
        let known = Set(settings.known)
        let handledKeys = Set(settings.handled)
        var addedTo: [Int: UUID] = [:]
        for course in courses { for a in course.assignments { if let id = a.lmsId { addedTo[id] = course.course.id } } }
        var open: [Int: [LMSProposal.Item]] = [:]
        var done: [Int: [(item: LMSProposal.Item, course: UUID?, proposable: Bool)]] = [:]
        for a in snapshot.assignments {
            let doable = !a.submitted && (a.due.map { $0 >= now } ?? true)
            if let course = addedTo[a.id] {
                done[a.classroom, default: []].append((.assignment(a), course, false))
            } else if handledKeys.contains(a.key) {
                done[a.classroom, default: []].append((.assignment(a), nil, doable))
            } else if doable {
                open[a.classroom, default: []].append(.assignment(a))
            }
        }
        for f in snapshot.files {
            if handledKeys.contains(f.key) {
                done[f.classroom, default: []].append((.file(f), nil, true))
            } else {
                open[f.classroom, default: []].append(.file(f))
            }
        }
        for n in snapshot.notices {
            if handledKeys.contains(n.key) {
                done[n.classroom, default: []].append((.notice(n), nil, true))
            } else {
                open[n.classroom, default: []].append(.notice(n))
            }
        }
        let sections = snapshot.classrooms.compactMap { room -> Section? in
            guard known.contains(room.id) else { return nil }
            let proposals = (open[room.id] ?? []).map { LMSProposal(item: $0, classroom: room) }
            let handled = (done[room.id] ?? []).map {
                Handled(proposal: LMSProposal(item: $0.item, classroom: room), course: $0.course, proposable: $0.proposable)
            }
            return proposals.isEmpty && handled.isEmpty ? nil : Section(classroom: room, proposals: proposals, handled: handled)
        }
        return LMSInbox(sections: sections.filter { !$0.proposals.isEmpty } + sections.filter { $0.proposals.isEmpty })
    }
}
