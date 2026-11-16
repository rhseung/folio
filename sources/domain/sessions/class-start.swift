import Foundation

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
