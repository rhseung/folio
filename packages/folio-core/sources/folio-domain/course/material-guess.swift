import Foundation

/// A file about to be brought in, as much as its name and first pages say.
public struct IncomingFile: Equatable, Sendable {
    public var name: String
    public var pages: Int?
    /// The first page is wider than tall: slides, not a printed page.
    public var landscape: Bool

    public init(name: String, pages: Int? = nil, landscape: Bool = false) {
        (self.name, self.pages, self.landscape) = (name, pages, landscape)
    }
}

/// Where the add sheet opens a file, and why. Only a starting point the user changes in the sheet.
public struct IntakeGuess: Equatable, Sendable {
    public enum Why: Equatable, Sendable {
        /// Words in the file name: `05_`, `HW3`, `syllabus`.
        case named(String)
        case slides(pages: Int)
        case book(pages: Int)

        public var text: String {
            switch self {
            case .named(let words): String(localized: .intakeWhyNamed(words))
            case .slides(let pages): String(localized: .intakeWhySlides(pages))
            case .book(let pages): String(localized: .intakeWhyBook(pages))
            }
        }
    }

    public enum SessionWhy: Equatable, Sendable {
        /// The name gave the week.
        case week(Int)
        case today
        case latest

        public var text: String {
            switch self {
            case .week(let week): String(localized: .intakeSessionWeek(week))
            case .today: String(localized: .intakeSessionToday)
            case .latest: String(localized: .intakeSessionLatest)
            }
        }
    }

    public var folder: String
    /// Nil when nothing about the file pointed anywhere and it sits in `Lectures`, where most files go.
    public var why: Why?
    public var session: UUID?
    public var sessionWhy: SessionWhy?

    public init(folder: String, why: Why? = nil, session: UUID? = nil, sessionWhy: SessionWhy? = nil) {
        (self.folder, self.why, self.session, self.sessionWhy) = (folder, why, session, sessionWhy)
    }
}

extension MaterialIntake {
    /// Read in order, the first that matches wins: a name says more than a page count, and `05_` more than any word.
    /// `places` are the folders the sheet offers besides `Lectures`; a guess never points elsewhere.
    public static func guess(_ file: IncomingFile, places: [String], sessions: [Session], now: Date, settings: Settings,
                             calendar: Calendar) -> IntakeGuess {
        let name = file.name.precomposedStringWithCanonicalMapping
        let lower = name.lowercased()
        let offered = { (folder: CourseFolder) in places.contains(folder.rawValue) ? folder.rawValue : nil }
        let lecture = { (why: IntakeGuess.Why?, week: Int?) in
            var guess = IntakeGuess(folder: CourseFolder.lectures.rawValue, why: why)
            (guess.session, guess.sessionWhy) = session(week: week, among: sessions, now: now, settings: settings, calendar: calendar)
            return guess
        }

        if let m = name.firstMatch(of: /^(\d{2})(?:-\d+)?_/), StandardLayout.isLectureFileName(name) {
            return lecture(.named(String(m.0)), Int(m.1))
        }
        if let (folder, words) = assignment(in: name, places: places) {
            return IntakeGuess(folder: folder, why: .named(words))
        }
        if let m = name.firstMatch(of: /기출|족보|past[\s_-]?exams?|previous[\s_-]?exams?/.ignoresCase()), let folder = offered(.inherited) {
            return IntakeGuess(folder: folder, why: .named(String(m.0)))
        }
        if let word = Keywords.syllabus.first(where: lower.contains), let folder = offered(.syllabus) {
            return IntakeGuess(folder: folder, why: .named(word))
        }
        if let word = Keywords.examFiles.flatMap(\.words).first(where: lower.contains), let folder = examFolder(for: lower, places: places) {
            return IntakeGuess(folder: folder, why: .named(word))
        }
        if let word = Keywords.textbook.first(where: lower.contains), let folder = offered(.textbooks) {
            return IntakeGuess(folder: folder, why: .named(word))
        }
        if let m = name.firstMatch(of: /exercises?|practice|연습/.ignoresCase()), let folder = offered(.exercises) {
            return IntakeGuess(folder: folder, why: .named(String(m.0)))
        }
        if let (words, week) = week(in: name) {
            return lecture(.named(words), week)
        }
        // Past a few hundred pages it is a book, whatever its shape; a lecture's deck stays well under that.
        if let pages = file.pages, pages >= 150, let folder = offered(.textbooks) {
            return IntakeGuess(folder: folder, why: .book(pages: pages))
        }
        if file.landscape, let pages = file.pages {
            return lecture(.slides(pages: pages), nil)
        }
        return lecture(nil, nil)
    }

    /// `Lecture 6`, `week3`, `5주차`. `[^a-z]` rather than `\b` in front: `_` is a word character, and `GT_lec3` is a
    /// common name.
    static func week(in name: String) -> (words: String, week: Int)? {
        if let m = name.firstMatch(of: /(?:^|[^a-z])((?:week|wk|lecture|lec)[\s_-]*(\d{1,2}))(?!\d)/.ignoresCase()) { return (String(m.1), Int(m.2)!) }
        if let m = name.firstMatch(of: /(\d{1,2})\s*주차/) { return (String(m.0), Int(m.1)!) }
        return nil
    }

    /// `HW3` → `Assignments/HW03`, but only to a folder that exists: the sheet can't make one.
    static func assignment(in name: String, places: [String]) -> (folder: String, words: String)? {
        let keyword = /(?:^|[^a-z])((hw|homework|assignment|assign|lab|sp|slow[\s_-]?problems?|report|project|reading|과제|숙제)[\s_-]*(\d{1,2}))(?!\d)/
        guard let m = name.firstMatch(of: keyword.ignoresCase()), let number = Int(m.3) else { return nil }
        let prefix: AssignmentKind = switch m.2.lowercased() {
        case "lab": .lab
        case "report": .report
        case "project": .project
        case "reading": .reading
        case let word where word == "sp" || word.hasPrefix("slow"): .slowProblem
        default: .homework
        }
        let base = CourseFolder.assignments.rawValue + "/"
        let folders = places.filter { $0.hasPrefix(base) }
        let numbered = folders.filter { StandardLayout.assignmentFolder(String($0.dropFirst(base.count)))?.number == number }
        guard let folder = numbered.first(where: { StandardLayout.assignmentFolder(String($0.dropFirst(base.count)))?.prefix == prefix.rawValue })
                ?? (numbered.count == 1 ? numbered.first : nil) else { return nil }
        return (folder, String(m.1))
    }

    /// The exam folder a seating chart or exam notice belongs to: the one its name says (midterm, final), else the
    /// latest, which is the one coming up.
    static func examFolder(for lower: String, places: [String]) -> String? {
        let exams = places.filter { $0.hasPrefix(CourseFolder.exams.rawValue + "/") }
        let said = { (word: Regex<Substring>) in lower.contains(word) ? exams.first { $0.lowercased().contains(word) } : nil }
        return said(Keywords.midterm) ?? said(Keywords.final) ?? exams.last
    }

    /// The class a lecture file is for. Slides often come before the class, so one later today counts as today's.
    /// With a week from the name, that week's class; without, the latest.
    static func session(week: Int?, among sessions: [Session], now: Date, settings: Settings,
                        calendar: Calendar) -> (UUID?, IntakeGuess.SessionWhy?) {
        let today = settings.studyDay(of: now, calendar: calendar)
        let isToday = { (s: Session) in settings.studyDay(of: s.date, calendar: calendar) == today }
        let held = sessions.filter { !$0.isCancelled }.sorted(by: Session.inOrder)
        let latest = { (among: [Session]) in among.last { $0.date <= now || isToday($0) } }
        if let week {
            // A week with no class (an old deck, a week not set up yet) gets none: today's class would take its week
            // in front of a name that says another.
            let ofWeek = held.filter { $0.week == week }
            return (latest(ofWeek) ?? ofWeek.first).map { ($0.id, .week(week)) } ?? (nil, nil)
        }
        guard let s = latest(held) else { return (nil, nil) }
        return (s.id, isToday(s) ? .today : .latest)
    }
}
