import Foundation

// GIST LMS (Coursemos on Moodle 3.2, #132). FolioLMS reads its pages into these values; the rules for what becomes a
// proposal live here so the app, the CLI and the tests ask one place.

/// An LMS course page ("강의실"). Its id is Moodle's course id, stable across terms.
public struct LMSClassroom: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var title: String
    /// "교과", "비교과", "교류강좌": the label Coursemos puts before the title.
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
    /// The activity's course-module id (`mod/assign/view.php?id=`).
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

/// A file activity (Coursemos `ubfile`). Whether it downloads is only known when its page is opened: allowed files
/// redirect to the original, others show only the Coursemos viewer, and those stay a link.
public struct LMSFile: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var classroom: Int
    public var title: String
    /// The week heading it sits under, such as "5주차 [9월28일 - 10월4일]".
    public var week: String?

    public init(id: Int, classroom: Int, title: String, week: String? = nil) {
        self.id = id
        self.classroom = classroom
        self.title = title
        self.week = week
    }

    public var key: LMSKey { .init(kind: .file, id: id) }
    public var url: URL { LMS.url("/mod/ubfile/view.php?id=\(id)") }

    /// `Lectures` names files `<week>_<title>`, so a download named `Ch5.pdf` under "5주차 […]" lands as
    /// `05_Ch5.pdf`. A name that already starts with a number keeps the professor's numbering.
    public func lectureName(_ downloaded: String) -> String {
        guard downloaded.first?.isNumber == false, let week, let number = Int(week.prefix { $0.isNumber }) else { return downloaded }
        return String(format: "%02d_", number) + downloaded
    }
}

public struct LMSNotice: Codable, Hashable, Sendable, Identifiable {
    /// The post's id (`bwid`); unique across boards.
    public var id: Int
    public var board: Int
    public var classroom: Int
    public var title: String
    public var author: String?
    /// The day it was posted, as the board shows it (no time).
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

/// Everything one sync read. A cache on this device; the settings hold what the user decided about it.
public struct LMSSnapshot: Codable, Hashable, Sendable {
    public var at: Date
    public var classrooms: [LMSClassroom]
    public var assignments: [LMSAssignment]
    public var files: [LMSFile]
    public var notices: [LMSNotice]

    public init(at: Date, classrooms: [LMSClassroom] = [], assignments: [LMSAssignment] = [], files: [LMSFile] = [],
                notices: [LMSNotice] = []) {
        self.at = at
        self.classrooms = classrooms
        self.assignments = assignments
        self.files = files
        self.notices = notices
    }

    /// The files and notices a classroom has now: seeing it the first time marks these handled, so only what comes later
    /// is proposed.
    public func current(in classroom: Int) -> [LMSKey] {
        files.filter { $0.classroom == classroom }.map(\.key) + notices.filter { $0.classroom == classroom }.map(\.key)
    }

    /// Replaces one classroom's items with `other`'s, keeping the rest.
    public mutating func merge(_ other: LMSSnapshot, in classroom: Int) {
        assignments.removeAll { $0.classroom == classroom }
        files.removeAll { $0.classroom == classroom }
        notices.removeAll { $0.classroom == classroom }
        assignments += other.assignments.filter { $0.classroom == classroom }
        files += other.files.filter { $0.classroom == classroom }
        notices += other.notices.filter { $0.classroom == classroom }
    }
}

/// One LMS item across syncs, written in settings as `assignment:139941`.
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

/// `settings.json`'s `lms`: shared by the user's devices through the GIST folder. The login lives in the keychain.
///
/// No classroom is tied to a course: one course can have two classrooms, and a classroom can be no course at all
/// (safety training). Each item picks its course when it is added.
public struct LMSSettings: Codable, Sendable, Equatable {
    /// Classrooms seen before. A classroom is proposed from only once it is here, and it gets here with its files and
    /// notices of that moment marked handled, so a new term doesn't arrive as hundreds of old posts.
    public var known: [Int]
    /// Items added or dismissed, so they aren't proposed again. Assignments are also kept off by their `lmsId`.
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

    /// Both lists stay sorted and without repeats, so two devices doing the same thing write the same file.
    public mutating func know(_ classrooms: [Int]) {
        known = Set(known).union(classrooms).sorted()
    }

    public mutating func mark(_ keys: [LMSKey], handled on: Bool) {
        var set = Set(handled)
        if on { set.formUnion(keys) } else { set.subtract(keys) }
        handled = set.sorted()
    }

    /// The snapshot's classrooms not seen before, which the next sync makes known.
    public func unseen(in snapshot: LMSSnapshot) -> [LMSClassroom] {
        let known = Set(known)
        return snapshot.classrooms.filter { !known.contains($0.id) }
    }
}

public enum LMS {
    public static let base = URL(string: "https://lms.gist.ac.kr")!
    /// Dates on the LMS pages are Korean local time with no zone written.
    public static let timeZone = TimeZone(identifier: "Asia/Seoul")!

    public static func url(_ path: String) -> URL { URL(string: path, relativeTo: base)!.absoluteURL }
}

/// One thing the LMS has that Folio doesn't yet, for the user to add to a course of their choice or dismiss.
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

/// What the proposals screen shows: a section per LMS classroom, under the classroom's own name.
public struct LMSInbox: Sendable, Equatable {
    /// An item no longer proposed: dismissed, marked when its classroom was first seen, or added. Kept in view so a
    /// dismissal made by mistake can be taken back.
    public struct Handled: Sendable, Equatable, Identifiable {
        public var proposal: LMSProposal
        /// The course an assignment is in by its `lmsId`.
        public var course: UUID?
        /// Whether taking the mark back would propose it. An assignment already in a course, handed in or past its
        /// deadline would not: `build` leaves it out of the proposals, so it would drop out of view altogether.
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
    /// The sections with something to propose, for the counts outside the proposals screen.
    public var waiting: [Section] { sections.filter { !$0.proposals.isEmpty } }
    public var isEmpty: Bool { proposals.isEmpty }

    /// - Only known classrooms propose (`LMSSettings.known`); one seen for the first time waits for the sync to mark
    ///   what it already holds.
    /// - An assignment is proposed while it can still be done: not handed in, and not past its deadline.
    /// - Nothing already handled, and no assignment any course already has by its `lmsId`, whichever course it went to.
    ///   Those are the section's `handled`. An assignment left to pass its deadline is neither; one dismissed before
///   it passed stays handled, but can't be proposed again.
    /// - Sections with something to propose come first, then those with only handled items; each part keeps the
    ///   dashboard's order. A classroom with neither has no section.
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
            if handledKeys.contains(f.key) { done[f.classroom, default: []].append((.file(f), nil, true)) } else { open[f.classroom, default: []].append(.file(f)) }
        }
        for n in snapshot.notices {
            if handledKeys.contains(n.key) { done[n.classroom, default: []].append((.notice(n), nil, true)) } else { open[n.classroom, default: []].append(.notice(n)) }
        }
        let sections = snapshot.classrooms.compactMap { room -> Section? in
            guard known.contains(room.id) else { return nil }
            let proposals = (open[room.id] ?? []).map { LMSProposal(item: $0, classroom: room) }
            let handled = (done[room.id] ?? []).map { Handled(proposal: LMSProposal(item: $0.item, classroom: room), course: $0.course, proposable: $0.proposable) }
            return proposals.isEmpty && handled.isEmpty ? nil : Section(classroom: room, proposals: proposals, handled: handled)
        }
        return LMSInbox(sections: sections.filter { !$0.proposals.isEmpty } + sections.filter { $0.proposals.isEmpty })
    }
}
