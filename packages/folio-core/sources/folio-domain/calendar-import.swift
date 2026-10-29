import Foundation

/// One class meeting from a calendar export. `course` is the course folder name, e.g. `GS1211 일반화학실험`.
public struct CalendarMeeting: Codable, Sendable, Equatable {
    public var course: String
    public var start: Date
    public var end: Date
    public var room: String
    public var topic: String
    /// The experiment's `Lab<NN>` number: the session links to that lab's unit. The parts of a two-session
    /// experiment share it.
    public var lab: Int?

    public init(course: String, start: Date, end: Date, room: String = "", topic: String = "", lab: Int? = nil) {
        self.course = course
        self.start = start
        self.end = end
        self.room = room
        self.topic = topic
        self.lab = lab
    }
}

/// One exam from a calendar export, for the course folder `course`.
public struct CalendarExam: Codable, Sendable, Equatable {
    public var course: String
    public var kind: ExamKind
    public var start: Date
    public var end: Date
    public var location: String
    public var memo: String

    public init(course: String, kind: ExamKind, start: Date, end: Date, location: String = "", memo: String = "") {
        self.course = course
        self.kind = kind
        self.start = start
        self.end = end
        self.location = location
        self.memo = memo
    }
}

public enum CalendarImporter {
    public struct Result: Sendable {
        public var file: CourseFile
        public var added: [Session]
        /// Existing sessions that only had a date and got the meeting's time or topic.
        public var filled: [Session]
        /// Sessions inside the calendar's span on a day it has no meeting for: the class was cancelled.
        public var cancelled: [Session]
        /// Set only when the course had no schedule.
        public var schedule: [ClassTime]
    }

    /// Adds a session for each meeting with none that day, preferring one at the meeting's time; existing sessions keep
    /// their week and index and only gain a missing time, topic or lab unit. Re-running adds nothing.
    public static func merge(_ meetings: [CalendarMeeting], into file: CourseFile, semesterStart: LocalDate,
                             calendar: Calendar, device: DeviceID, now: Date) -> Result {
        var file = file
        var added: [Session] = []
        var filled: [Session] = []
        guard let first = semesterStart.date(in: calendar) else { return Result(file: file, added: [], filled: [], cancelled: [], schedule: []) }
        let firstMonday = calendar.startOfWeek(containing: first)
        // A session stands for one meeting only, so a lecture and a recitation on the same day stay two.
        var matched: Set<UUID> = []
        for m in meetings.sorted(by: { $0.start < $1.start }) {
            let sameDay = file.sessions.indices.filter { !matched.contains(file.sessions[$0].id) && calendar.isDate(file.sessions[$0].date, inSameDayAs: m.start) }
            if let i = sameDay.first(where: { file.sessions[$0].date == m.start }) ?? sameDay.first {
                let before = file.sessions[i]
                matched.insert(before.id)
                // Imported sessions carry only a day; midnight means no time was known.
                if before.date == calendar.startOfDay(for: before.date) { file.sessions[i].date = m.start }
                if before.topic.isEmpty { file.sessions[i].topic = m.topic }
                if let lab = m.lab { file.linkLab(lab, session: before.id, topic: m.topic, device: device, at: now) }
                if file.sessions[i] != before {
                    file.sessions[i].touch(by: device, at: now)
                    filled.append(file.sessions[i])
                }
                continue
            }
            let week = calendar.dateComponents([.day], from: firstMonday, to: calendar.startOfDay(for: m.start)).day! / 7 + 1
            let index = (file.sessions.filter { $0.week == week }.map(\.index).max() ?? 0) + 1
            var s = Session(device: device, at: now, week: week, index: index, date: m.start)
            s.topic = m.topic
            file.sessions.append(s)
            matched.insert(s.id)
            if let lab = m.lab { file.linkLab(lab, session: s.id, topic: m.topic, device: device, at: now) }
            added.append(file.sessions.last!)
        }
        var cancelled: [Session] = []
        let days = Set(meetings.map { calendar.startOfDay(for: $0.start) })
        if let from = days.min(), let to = days.max() {
            for i in file.sessions.indices where !file.sessions[i].isCancelled {
                let day = calendar.startOfDay(for: file.sessions[i].date)
                guard day >= from, day <= to, !days.contains(day) else { continue }
                file.sessions[i].isCancelled = true
                file.sessions[i].touch(by: device, at: now)
                cancelled.append(file.sessions[i])
            }
        }
        file.sessions.sort { $0.date < $1.date }
        var schedule: [ClassTime] = []
        if file.course.schedule.isEmpty {
            schedule = weeklySlots(meetings, calendar: calendar)
            file.course.schedule = schedule
        }
        return Result(file: file, added: added, filled: filled, cancelled: cancelled, schedule: schedule)
    }

    /// Times that repeat at least three times; one-off meetings (a makeup, a single extra session) are left out.
    static func weeklySlots(_ meetings: [CalendarMeeting], calendar: Calendar) -> [ClassTime] {
        let slots = meetings.map { m -> ClassTime in
            let minute = { (d: Date) in calendar.component(.hour, from: d) * 60 + calendar.component(.minute, from: d) }
            return ClassTime(weekday: calendar.isoWeekday(of: m.start), startMinute: minute(m.start), endMinute: minute(m.end), room: m.room)
        }
        let counts = Dictionary(slots.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.filter { $0.value >= 3 }.keys.sorted { ($0.weekday, $0.startMinute) < ($1.weekday, $1.startMinute) }
    }

    /// Session -> note pairs where a session's topic is a note's title and neither is linked yet.
    public static func noteLinks(sessions: [Session], notes: [(id: UUID, title: String, sessionId: UUID?)]) -> [(session: UUID, note: UUID)] {
        let free = notes.filter { $0.sessionId == nil }
        return sessions.compactMap { s in
            guard !s.topic.isEmpty, s.reviewNoteId == nil,
                  let note = free.first(where: { $0.title == s.topic }) else { return nil }
            return (s.id, note.id)
        }
    }

    public struct ExamResult: Sendable {
        public var file: CourseFile
        public var added: [Exam]
        public var filled: [Exam]
        /// The course already has this kind of exam on another day; the calendar and the file disagree, so nothing changes.
        public var conflicts: [(exam: Exam, calendar: CalendarExam)]
    }

    /// An exam of the same kind that has no time yet or is on the same day gains the calendar's time, room and memo
    /// where they are empty; otherwise a new exam is added. Re-running adds nothing.
    public static func mergeExams(_ exams: [CalendarExam], into file: CourseFile, calendar: Calendar, device: DeviceID, now: Date) -> ExamResult {
        var file = file
        var added: [Exam] = [], filled: [Exam] = []
        var conflicts: [(exam: Exam, calendar: CalendarExam)] = []
        for e in exams.sorted(by: { $0.start < $1.start }) {
            let same = file.exams.indices.filter { file.exams[$0].kind == e.kind }
            if let i = same.first(where: { file.exams[$0].start.map { calendar.isDate($0, inSameDayAs: e.start) } ?? true }) {
                var x = file.exams[i]
                if x.start == nil || x.start == calendar.startOfDay(for: x.start!) { x.start = e.start }
                if x.end == nil { x.end = e.end }
                if x.location.isEmpty { x.location = e.location }
                if x.memo.isEmpty { x.memo = e.memo }
                if x != file.exams[i] {
                    x.touch(by: device, at: now)
                    file.exams[i] = x
                    filled.append(x)
                }
            } else if let i = same.first, e.kind != .quiz && e.kind != .other {
                // A course has one midterm and one final; quizzes and others can be many.
                conflicts.append((file.exams[i], e))
            } else {
                var x = Exam(device: device, at: now, kind: e.kind, title: e.kind.folderName(number: same.count + 1) ?? "", start: e.start, end: e.end, location: e.location)
                x.memo = e.memo
                file.exams.append(x)
                added.append(x)
            }
        }
        return ExamResult(file: file, added: added, filled: filled, conflicts: conflicts)
    }
}
