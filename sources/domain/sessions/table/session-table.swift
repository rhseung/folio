import FolioCore
import Foundation

// 회차 화면의 주차 × 수업 요일 표다. 줄은 월요일에 시작하는 주 하나, 열은 시간표의 수업 요일 하나이고, 끝의 "그 밖" 칸이
// 수업 요일이 아닌 날의 일(보강, 시험, 과제 마감)을 모은다.
public struct SessionTable: Sendable {
    public struct Column: Sendable, Hashable, Identifiable {
        // ISO 8601 요일이다.
        public let weekday: Int
        public let slots: [ClassTime]
        public var id: Int { weekday }
    }

    public struct Cell: Sendable, Identifiable {
        // 수업 요일 칸이면 그 요일, "그 밖" 칸이면 nil이다.
        public let weekday: Int?
        public let day: LocalDate?
        public let isToday: Bool
        public let entries: [SessionTableEntry]
        public var id: Int { weekday ?? 0 }
    }

    public struct Week: Sendable, Identifiable {
        public let number: Int
        public let start: LocalDate
        public let isThisWeek: Bool
        public let isExamWeek: Bool
        // 수업 요일 칸이 열 순서대로 오고, 마지막이 "그 밖" 칸이다.
        public let cells: [Cell]
        public let agenda: [SessionAgendaDay]
        public var id: LocalDate { start }
        public var end: LocalDate { start.adding(days: 6) }
        public var other: Cell { cells[cells.count - 1] }
    }

    public let columns: [Column]
    public let weeks: [Week]
    public let thisWeek: LocalDate

    // 공부일로 센다. 새벽 4시 전에는 어제가 오늘이고, 월요일 새벽이면 지난주가 이번 주다.
    public init(
        _ file: CourseFile, planned: [Session] = [], semester: Semester? = nil, now: Date, settings: Settings, asksWrapUp: Bool = true,
        calendar: Calendar
    ) {
        let today = settings.studyDay(of: now, calendar: calendar)
        thisWeek = Self.monday(of: today)
        columns = Dictionary(grouping: file.course.schedule, by: \.weekday).sorted { $0.key < $1.key }.map {
            Column(weekday: $0.key, slots: $0.value.sorted { $0.startMinute < $1.startMinute })
        }

        let classes = (file.sessions + planned).filter { !$0.isCancelled && $0.date > now }
        let next = classes.min(by: Session.inOrder).map(\.date)
        let outline = UnitTree.outline(file.units).map(\.unit)
        let lectures = Set(file.lectureFiles.map(\.id))
        var entries = file.sessions.map {
            SessionTableEntry.session(
                $0, planned: false, next: $0.date == next, in: file, outline: outline, lectures: lectures, now: now, settings: settings,
                asksWrapUp: asksWrapUp, calendar: calendar)
        }
        // 저장한 회차와 같은 시각의 예정 수업은 그 회차가 대신한다.
        let saved = Set(file.sessions.map(\.date))
        entries += planned.filter { !saved.contains($0.date) }.map {
            SessionTableEntry.session(
                $0, planned: true, next: $0.date == next && !saved.contains($0.date), in: file, outline: outline, lectures: lectures,
                now: now, settings: settings, asksWrapUp: false, calendar: calendar)
        }
        entries += file.exams.compactMap { e in
            e.start.map { SessionTableEntry.exam(e, at: $0, in: file, outline: outline, calendar: calendar) }
        }
        entries += file.assignments.compactMap { a in a.due.map { SessionTableEntry.deadline(a, at: $0, now: now, calendar: calendar) } }
        entries = Self.ordered(entries)

        let days = entries.map(\.day) + [semester?.start, semester?.end].compactMap { $0 }
        guard let first = days.min(), let last = days.max() else {
            weeks = []
            return
        }
        let anchor = Self.monday(of: semester?.start ?? first)
        let examWeeks = semester?.examWeeks ?? []
        let byWeek = Dictionary(grouping: entries) { Self.monday(of: $0.day) }
        let weekdays = Set(columns.map(\.weekday))

        var weeks: [Week] = []
        var start = Self.monday(of: first)
        while start <= last {
            let all = byWeek[start] ?? []
            let number = max(1, anchor.days(until: start) / 7 + 1)
            var cells = columns.map { column in
                let day = start.adding(days: column.weekday - 1)
                return Cell(weekday: column.weekday, day: day, isToday: day == today, entries: all.filter { $0.day == day })
            }
            cells.append(Cell(weekday: nil, day: nil, isToday: false, entries: all.filter { !weekdays.contains(Self.weekday(of: $0.day)) }))
            weeks.append(
                Week(
                    number: number, start: start, isThisWeek: start == thisWeek, isExamWeek: examWeeks.contains(number), cells: cells,
                    agenda: SessionAgendaDay.days(all, weekStart: start, today: today)))
            start = start.adding(days: 7)
        }
        self.weeks = weeks
    }

    public func week(containing session: UUID) -> LocalDate? {
        weeks.first { w in w.cells.contains { c in c.entries.contains { $0.session?.id == session } } }?.id
    }

    // `sort`는 안정 정렬이 아니므로 같은 시각은 원래 순서(회차, 예정 수업, 시험, 마감)로 정한다.
    static func ordered(_ entries: [SessionTableEntry]) -> [SessionTableEntry] {
        entries.enumerated().sorted { a, b in
            if a.element.date != b.element.date { return a.element.date < b.element.date }
            if let x = a.element.session, let y = b.element.session { return Session.inOrder(x, y) }
            return a.offset < b.offset
        }
        .map(\.element)
    }

    public static func weekday(of day: LocalDate) -> Int {
        // Sakamoto의 요일 공식이다. 결과 0이 일요일이므로 월요일이 1, 일요일이 7이 되게 옮긴다.
        let offsets = [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4]
        let y = day.month < 3 ? day.year - 1 : day.year
        let sunday = (y + y / 4 - y / 100 + y / 400 + offsets[day.month - 1] + day.day) % 7
        return (sunday + 6) % 7 + 1
    }

    public static func monday(of day: LocalDate) -> LocalDate { day.adding(days: 1 - weekday(of: day)) }
}
