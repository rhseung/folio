import Foundation

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

    public enum OpenIn: String, Codable, Sendable, CaseIterable {
        case splitTab, currentTab
    }

    public enum Screen: String, Codable, Sendable, CaseIterable {
        case front, notify
    }

    public var recording = Recording.off
    public var recordingOffsetMinutes = 0
    public var stopsRecording = false
    public var stopAfterMinutes = 0
    public var roughNote = RoughNote.off
    public var roughNotePlace = Place.here
    public var lecture = Lecture.off
    public var lecturePlace = Place.beside
    public var openIn = OpenIn.splitTab
    public var allLectures = false
    public var resumesLecture = true
    public var screen = Screen.notify
    public var preset: String?
    // JSON은 다른 타입을 키로 쓴 딕셔너리를 평평한 배열로 쓰므로, 과목 ID를 UUID가 아니라 문자열 키로 둔다.
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

    func lead(course: UUID) -> TimeInterval {
        isOn(.recording, course: course) ? TimeInterval(max(0, -recordingOffsetMinutes) * 60) : 0
    }
}

public struct StartingClass: Equatable, Sendable {
    public var courseId: UUID
    public var sessionId: UUID?
    public var start: Date
    public var end: Date

    public init(courseId: UUID, sessionId: UUID?, start: Date, end: Date) {
        self.courseId = courseId
        self.sessionId = sessionId
        self.start = start
        self.end = end
    }

    // 시간표의 수업을 그 시작 시각에 회차로 저장해도 키가 같아야, 그 수업에 한 일을 두 번 하지 않는다.
    public var key: String { "\(courseId.uuidString)@\(Int(start.timeIntervalSinceReferenceDate))" }
}

public enum ClassStart {
    public enum Step: String, Hashable, Sendable, CaseIterable {
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

    // 겹치는 수업 중에서는 가장 늦게 시작한 수업을 고른다. 시간을 넘긴 수업보다 학생이 옮겨 간 수업이 앞서기 때문이다.
    // 같은 순간에 시작하는 수업이 둘이면 아무것도 고르지 않는다. 다른 과목의 녹음을 시작하는 것이 아무것도 시작하지
    // 않는 것보다 나쁘기 때문이다.
    public static func starting(_ courses: [Course], settings: Settings, now: Date, calendar: Calendar) -> StartingClass? {
        let candidates = courses.flatMap { classes(of: $0, settings: settings, around: now, calendar: calendar) }.filter { c in
            c.start.addingTimeInterval(-settings.classStart.lead(course: c.courseId)) <= now && now < c.end
        }
        guard let latest = candidates.map(\.start).max() else { return nil }
        let last = candidates.filter { $0.start == latest }
        return last.count == 1 ? last[0] : nil
    }

    public static func next(_ courses: [Course], settings: Settings, now: Date, calendar: Calendar) -> StartingClass? {
        courses.flatMap { classes(of: $0, settings: settings, around: now, days: 9, calendar: calendar, onlyOn: false) }
            .filter { $0.end > now }
            .min { $0.start < $1.start }
    }

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

        // 자정 전에 시작한 수업도 자정 뒤에 찾도록 전날부터 본다.
        let planned = SessionPlanner.planned(
            schedule: file.course.schedule, sessions: file.sessions, from: course.term?.start, to: course.term?.end,
            examWeeks: course.term?.examWeeks ?? [], days: days,
            now: now.addingTimeInterval(-86_400), calendar: calendar
        )
        .map { StartingClass(courseId: id, sessionId: nil, start: $0.date, end: $0.end) }
        return sessions + planned
    }

    public static func due(_ c: StartingClass, settings: ClassStartSettings, now: Date) -> Set<Step> {
        guard now < c.end, settings.isOn(for: c.courseId) else { return [] }
        var due: Set<Step> = now >= c.start ? [.open] : []
        if settings.isOn(.recording, course: c.courseId), now >= recordingStart(c, settings: settings) { due.insert(.recording) }
        return due
    }

    public static func recordingStart(_ c: StartingClass, settings: ClassStartSettings) -> Date {
        c.start.addingTimeInterval(TimeInterval(settings.recordingOffsetMinutes * 60))
    }

    public static func recordingStop(_ c: StartingClass, settings: ClassStartSettings) -> Date? {
        guard settings.stopsRecording else { return nil }
        return max(c.end.addingTimeInterval(TimeInterval(settings.stopAfterMinutes * 60)), recordingStart(c, settings: settings))
    }
}

extension CourseFile {
    public func startingLectures(for session: Session, all: Bool, resumes: Bool) -> [(material: UUID, page: Int?)] {
        let linked = lectureFiles.filter { !routes(of: $0, to: .session(session.id)).isEmpty }
        return (all ? linked : Array(linked.prefix(1))).map { m in (m.id, resumes ? resumePage(of: m.id, for: session) : nil) }
    }
}
