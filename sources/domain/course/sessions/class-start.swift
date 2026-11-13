import Foundation

/// What the app does by itself when a class starts (#391): the recording, the rough note and the linked lectures.
/// In settings.json, so every device does the same. Every item starts off.
public struct ClassStartSettings: Codable, Sendable, Equatable {
    public enum Item: String, Codable, Sendable, CaseIterable {
        case recording, roughNote, lecture
    }

    public enum Recording: String, Codable, Sendable, CaseIterable {
        case off, ask, start
    }

    public enum RoughNote: String, Codable, Sendable, CaseIterable {
        case off
        case openExisting
        case create
    }

    public enum Lecture: String, Codable, Sendable, CaseIterable {
        case off, open
    }

    public enum Place: String, Codable, Sendable, CaseIterable {
        case here, beside, tab, window
    }

    /// Where the rough note and the lectures open (2026-11-09 사용자): together in a new tab, side by side as the
    /// layout chosen for it lays them out (`Settings.classStartPreset`, "수업 중" unless another is chosen), or in the
    /// tab in front, each at its own `Place`.
    public enum OpenIn: String, Codable, Sendable, CaseIterable {
        case splitTab, currentTab
    }

    public enum Screen: String, Codable, Sendable, CaseIterable {
        case front, notify
    }

    public var recording = Recording.off
    /// From the class's start: negative before it, positive after.
    public var recordingOffsetMinutes = 0
    public var stopsRecording = false
    /// From the class's end, when `stopsRecording`: negative before it, positive after (#416).
    public var stopAfterMinutes = 0
    public var roughNote = RoughNote.off
    public var roughNotePlace = Place.here
    public var lecture = Lecture.off
    public var lecturePlace = Place.beside
    public var openIn = OpenIn.splitTab
    /// Every linked lecture rather than the first.
    public var allLectures = false
    /// At the page after where the last class stopped, when one did.
    public var resumesLecture = true
    public var screen = Screen.notify
    /// The layout the pages open in (`Settings.classStartPreset`), by id; nil for "수업 중".
    public var preset: String?
    /// Items a course turns off, by course ID (a course where recording isn't allowed). Strings, not UUIDs: JSON
    /// writes a dictionary keyed by anything else as a flat array.
    public var courseOff: [String: [Item]] = [:]

    public init() {}

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self()
        recording = try c.value(.recording, or: d.recording)
        recordingOffsetMinutes = try c.value(.recordingOffsetMinutes, or: d.recordingOffsetMinutes)
        stopsRecording = try c.value(.stopsRecording, or: d.stopsRecording)
        stopAfterMinutes = try c.value(.stopAfterMinutes, or: d.stopAfterMinutes)
        roughNote = try c.value(.roughNote, or: d.roughNote)
        roughNotePlace = try c.value(.roughNotePlace, or: d.roughNotePlace)
        lecture = try c.value(.lecture, or: d.lecture)
        lecturePlace = try c.value(.lecturePlace, or: d.lecturePlace)
        openIn = try c.value(.openIn, or: d.openIn)
        allLectures = try c.value(.allLectures, or: d.allLectures)
        resumesLecture = try c.value(.resumesLecture, or: d.resumesLecture)
        screen = try c.value(.screen, or: d.screen)
        preset = try c.decodeIfPresent(String.self, forKey: .preset)
        courseOff = try c.value(.courseOff, or: d.courseOff)
    }

    public func off(for course: UUID) -> Set<Item> { Set(courseOff[course.uuidString] ?? []) }

    /// Kept in `Item` order, and dropped when nothing is off, so the file only names courses that differ.
    public mutating func setOff(_ items: Set<Item>, for course: UUID) {
        courseOff[course.uuidString] = items.isEmpty ? nil : Item.allCases.filter(items.contains)
    }

    public func isOn(_ item: Item, course: UUID) -> Bool {
        guard !off(for: course).contains(item) else { return false }
        return switch item {
        case .recording: recording != .off
        case .roughNote: roughNote != .off
        case .lecture: lecture != .off
        }
    }

    public func isOn(for course: UUID) -> Bool { Item.allCases.contains { isOn($0, course: course) } }

    /// Before the class when the recording starts ahead of it, so the class counts from then.
    func lead(course: UUID) -> TimeInterval {
        isOn(.recording, course: course) ? TimeInterval(max(0, -recordingOffsetMinutes) * 60) : 0
    }
}

/// A class the app may start by itself: a session, or a class the timetable holds that no session stands for yet.
public struct StartingClass: Equatable, Sendable {
    public var courseId: UUID
    /// Nil for the timetable's class, which becomes a session when something is done for it.
    public var sessionId: UUID?
    public var start: Date
    public var end: Date

    public init(courseId: UUID, sessionId: UUID?, start: Date, end: Date) {
        self.courseId = courseId
        self.sessionId = sessionId
        self.start = start
        self.end = end
    }

    /// The same before and after the timetable's class is saved as a session at its start, so what was done for it
    /// is done once.
    public var key: String { "\(courseId.uuidString)@\(Int(start.timeIntervalSinceReferenceDate))" }
}

public enum ClassStart {
    /// What comes due for a class, each done once.
    public enum Step: String, Hashable, Sendable, CaseIterable {
        /// Going to the class: its rough note, its lectures and the session itself.
        case open
        case recording
    }

    public struct Course: Sendable {
        public var file: CourseFile
        public var term: Semester?

        public init(file: CourseFile, term: Semester?) {
            self.file = file
            self.term = term
        }
    }

    /// The class starting now: from its start (from its recording's, when that comes first) to its end. A cancelled
    /// session, a class already over, one in an exam week and a course with every item off never are. A session
    /// with no end of its own and no slot (a date-only import) has no known time, so it never starts either, as it
    /// is never under way (`TodaySummary.ongoingClass`). Of classes that overlap, the one that started last wins: a
    /// class running over is behind the one the student has gone to. Two starting at the same moment leave nothing,
    /// since starting the wrong course's recording is worse than starting none.
    /// Clock time only: a class past midnight is the one under way then, whichever study day it falls in.
    public static func starting(_ courses: [Course], settings: Settings, now: Date, calendar: Calendar) -> StartingClass? {
        let candidates = courses.flatMap { classes(of: $0, settings: settings, around: now, calendar: calendar) }.filter { c in
            c.start.addingTimeInterval(-settings.classStart.lead(course: c.courseId)) <= now && now < c.end
        }
        guard let latest = candidates.map(\.start).max() else { return nil }
        let last = candidates.filter { $0.start == latest }
        return last.count == 1 ? last[0] : nil
    }

    /// The class under way at `now`, or else the next to start, whatever is set to start by itself: the class the
    /// settings' recording span is shown for (`9:55 – 11:20`).
    public static func next(_ courses: [Course], settings: Settings, now: Date, calendar: Calendar) -> StartingClass? {
        courses.flatMap { classes(of: $0, settings: settings, around: now, days: 9, calendar: calendar, onlyOn: false) }
            .filter { $0.end > now }
            .min { $0.start < $1.start }
    }

    /// The course's classes near `now`: its sessions with a known end, and the timetable's classes from the day
    /// before to `days - 2` days after that no session stands for (`SessionPlanner.planned`).
    static func classes(
        of course: Course, settings: Settings, around now: Date, days: Int = 3, calendar: Calendar,
        onlyOn: Bool = true
    ) -> [StartingClass] {
        let file = course.file
        let id = file.course.id
        guard !onlyOn || settings.classStart.isOn(for: id) else { return [] }
        let sessions: [StartingClass] = file.sessions.compactMap { s in
            guard !s.isCancelled, let end = s.end(schedule: file.course.schedule, calendar: calendar) else { return nil }
            return StartingClass(courseId: id, sessionId: s.id, start: s.date, end: end)
        }

        // From the day before, so a class that began before midnight is still found after it.
        let planned = SessionPlanner.planned(
            schedule: file.course.schedule, sessions: file.sessions, from: course.term?.start, to: course.term?.end,
            examWeeks: course.term?.examWeeks ?? [], days: days,
            now: now.addingTimeInterval(-86_400), calendar: calendar
        )
        .map { StartingClass(courseId: id, sessionId: nil, start: $0.date, end: $0.end) }
        return sessions + planned
    }

    /// The steps whose time has come: going to the class once it starts, and the recording at its own time. Nothing
    /// once the class is over.
    public static func due(_ c: StartingClass, settings: ClassStartSettings, now: Date) -> Set<Step> {
        guard now < c.end, settings.isOn(for: c.courseId) else { return [] }
        var due: Set<Step> = now >= c.start ? [.open] : []
        if settings.isOn(.recording, course: c.courseId), now >= recordingStart(c, settings: settings) { due.insert(.recording) }
        return due
    }

    public static func recordingStart(_ c: StartingClass, settings: ClassStartSettings) -> Date {
        c.start.addingTimeInterval(TimeInterval(settings.recordingOffsetMinutes * 60))
    }

    /// When a recording the class started stops by itself; nil when it runs until stopped. Never before it starts:
    /// a stop set before the end of a short class would otherwise come ahead of the start.
    public static func recordingStop(_ c: StartingClass, settings: ClassStartSettings) -> Date? {
        guard settings.stopsRecording else { return nil }
        return max(c.end.addingTimeInterval(TimeInterval(settings.stopAfterMinutes * 60)), recordingStart(c, settings: settings))
    }
}

extension CourseFile {
    /// The lecture files linked to the class (`routes`), in the order `Lectures` names them: the first only unless
    /// `all`, each at the page after where the last class stopped when `resumes` and one did.
    public func startingLectures(for session: Session, all: Bool, resumes: Bool) -> [(material: UUID, page: Int?)] {
        let linked = lectureFiles.filter { !routes(of: $0, to: .session(session.id)).isEmpty }
        return (all ? linked : Array(linked.prefix(1))).map { m in (m.id, resumes ? resumePage(of: m.id, for: session) : nil) }
    }
}
