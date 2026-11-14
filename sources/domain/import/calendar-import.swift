import Foundation

public struct CalendarMeeting: Codable, Sendable, Equatable {
    public var course: String
    public var start: Date
    public var end: Date
    public var room: String
    public var topic: String
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

public struct CalendarExam: Codable, Sendable, Equatable {
    public var course: String
    public var title: String
    public var start: Date
    public var end: Date
    public var location: String
    public var memo: String

    public init(course: String, title: String, start: Date, end: Date, location: String = "", memo: String = "") {
        self.course = course
        self.title = title
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
        public var filled: [Session]
        public var titles: [UUID: String]
        public var cancelled: [Session]
        public var schedule: [ClassTime]
    }

    public static func merge(
        _ meetings: [CalendarMeeting], into file: CourseFile, semesterStart: LocalDate,
        calendar: Calendar, device: DeviceID, now: Date
    ) -> Result {
        var file = file
        var added: [Session] = []
        var filled: [Session] = []
        var titles: [UUID: String] = [:]
        guard let first = semesterStart.date(in: calendar) else {
            return Result(file: file, added: [], filled: [], titles: [:], cancelled: [], schedule: [])
        }
        let firstMonday = calendar.startOfWeek(containing: first)
        // 회차 하나는 모임 하나만 나타내므로, 같은 날의 강의와 리시테이션은 두 회차로 남는다.
        var matched: Set<UUID> = []
        for m in meetings.sorted(by: { $0.start < $1.start }) {
            let sameDay = file.sessions.indices.filter {
                !matched.contains(file.sessions[$0].id) && calendar.isDate(file.sessions[$0].date, inSameDayAs: m.start)
            }
            if let i = sameDay.first(where: { file.sessions[$0].date == m.start }) ?? sameDay.first {
                let before = file.sessions[i]
                matched.insert(before.id)
                titles[before.id] = m.topic
                // 가져온 회차는 날만 가지므로, 자정이면 시각을 몰랐다는 뜻이다.
                if before.date == calendar.startOfDay(for: before.date) { file.sessions[i].date = m.start }
                if let lab = m.lab { file.linkLab(lab, session: before.id, experiment: m.topic, device: device, at: now) }
                if file.sessions[i] != before {
                    file.sessions[i].touch(by: device, at: now)
                    filled.append(file.sessions[i])
                }
                continue
            }
            let week = calendar.dateComponents([.day], from: firstMonday, to: calendar.startOfDay(for: m.start)).day! / 7 + 1
            let s = Session(device: device, at: now, week: week, date: m.start)
            file.sessions.append(s)
            matched.insert(s.id)
            titles[s.id] = m.topic
            if let lab = m.lab { file.linkLab(lab, session: s.id, experiment: m.topic, device: device, at: now) }
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

        file.sessions.sort(by: Session.inOrder)
        var schedule: [ClassTime] = []
        if file.course.schedule.isEmpty {
            schedule = weeklySlots(meetings, calendar: calendar)
            file.course.schedule = schedule
        }
        return Result(file: file, added: added, filled: filled, titles: titles, cancelled: cancelled, schedule: schedule)
    }

    // 보강이나 한 번뿐인 추가 수업을 빼도록, 세 번 이상 되풀이되는 시각만 주간 시간으로 본다.
    static func weeklySlots(_ meetings: [CalendarMeeting], calendar: Calendar) -> [ClassTime] {
        let slots = meetings.map { m -> ClassTime in
            let minute = { (d: Date) in calendar.component(.hour, from: d) * 60 + calendar.component(.minute, from: d) }
            return ClassTime(
                weekday: calendar.isoWeekday(of: m.start), startMinute: minute(m.start), endMinute: minute(m.end), room: m.room)
        }
        let counts = Dictionary(slots.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.filter { $0.value >= 3 }.keys.sorted { ($0.weekday, $0.startMinute) < ($1.weekday, $1.startMinute) }
    }

    // 단원 노트나 초안 노트를 복습 노트로 바꾸면 그 노트의 단원이나 종류를 잃으므로, 자유 노트와 복습 노트만 잇는다.
    // 제목이 같은 두 회차는 노트 하나를 나눠 쓸 수 없으므로, 노트는 순서상 첫 회차 하나에만 잇는다.
    public static func noteLinks(sessions: [Session], titles: [UUID: String], notes: [(id: UUID, title: String, meta: NoteMeta)]) -> [(
        session: UUID, note: UUID
    )] {
        var free = notes.filter { $0.meta.sessionId == nil && ($0.meta.kind == .free || $0.meta.kind == .review) }
        return sessions.sorted(by: Session.inOrder).compactMap { s in
            guard let title = titles[s.id], !title.isEmpty, s.reviewNoteId == nil,
                let i = free.firstIndex(where: { $0.title == title })
            else { return nil }
            return (s.id, free.remove(at: i).id)
        }
    }

    public struct ExamResult: Sendable {
        public var file: CourseFile
        public var added: [Exam]
        public var filled: [Exam]
        public var conflicts: [(exam: Exam, calendar: CalendarExam)]
    }

    public static func mergeExams(_ exams: [CalendarExam], into file: CourseFile, calendar: Calendar, device: DeviceID, now: Date)
        -> ExamResult
    {
        var file = file
        var added: [Exam] = [], filled: [Exam] = []
        var conflicts: [(exam: Exam, calendar: CalendarExam)] = []
        for e in exams.sorted(by: { $0.start < $1.start }) {
            let same = file.exams.indices.filter { file.exams[$0].title == e.title }
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
            } else if let i = same.first {
                conflicts.append((file.exams[i], e))
            } else {
                var x = Exam(
                    device: device, at: now, title: e.title, start: e.start, end: e.end, location: e.location,
                    folder: MaterialIntake.examFolder(title: e.title, among: file.exams))
                x.memo = e.memo
                file.exams.append(x)
                added.append(x)
            }
        }
        return ExamResult(file: file, added: added, filled: filled, conflicts: conflicts)
    }
}
