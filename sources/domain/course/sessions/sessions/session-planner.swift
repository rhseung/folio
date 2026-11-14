import Foundation

public enum SessionPlanner {
    public struct Suggestion: Sendable, Equatable {
        public var date: Date
        public var end: Date
        public var room: String
        public var link: String?
    }

    public static func suggestion(
        schedule: [ClassTime], sessions: [Session], from start: LocalDate?, to end: LocalDate?,
        examWeeks: Set<Int> = [], now: Date, calendar: Calendar
    ) -> Suggestion? {
        planned(
            schedule: schedule, sessions: sessions, from: start, to: end, examWeeks: examWeeks,
            days: 8, now: now, calendar: calendar
        ).first
    }

    public static func planned(
        schedule: [ClassTime], sessions: [Session], from start: LocalDate?, to end: LocalDate?,
        examWeeks: Set<Int> = [], days: Int? = nil,
        now: Date, calendar: Calendar
    ) -> [Suggestion] {
        guard !schedule.isEmpty else { return [] }
        let today = calendar.startOfDay(for: now)
        let anchor = start?.date(in: calendar)
        let limit = days ?? (end == nil ? 8 : Int.max)
        let dates = sessions.map(\.date)
        let dateOnly = Set(dates)

        var result: [Suggestion] = []
        var offset = 0
        while offset < limit {
            let day = calendar.date(byAdding: .day, value: offset, to: today)!
            offset += 1
            let local = LocalDate(day, in: calendar)
            // 시작이 끝보다 뒤로 저장된 학기에서 날을 끝없이 건너뛰지 않도록 끝을 먼저 본다.
            if let end, local > end { break }
            if let start, local < start { continue }
            if let anchor, examWeeks.contains(week(of: day, anchor: anchor, calendar: calendar)) { continue }

            let weekday = calendar.isoWeekday(of: day)
            for slot in schedule.filter({ $0.weekday == weekday }).sorted(by: { $0.startMinute < $1.startMinute }) {
                let begin = calendar.date(byAdding: .minute, value: slot.startMinute, to: day)!
                let finish = calendar.date(byAdding: .minute, value: slot.endMinute, to: day)!
                guard finish > now else { continue }
                // 늦게 시작한 수업이나 시간표와 다르게 시작하는 캘린더 일정에서 가져온 수업도 그 수업이므로, 시작 시각만이 아니라
                // 시간 안 어디든 본다. 시간표 밖의 보강은 따로 남는다.
                if !dateOnly.contains(day) && !dates.contains(where: { $0 >= begin && $0 < finish }) {
                    result.append(Suggestion(date: begin, end: finish, room: slot.room, link: slot.link))
                }
            }
        }
        return result
    }

    public static func session(
        at date: Date, sessions: [Session], termStart: LocalDate?,
        calendar: Calendar, device: DeviceID, now: Date
    ) -> Session {
        let anchor = termStart?.date(in: calendar) ?? sessions.map(\.date).min() ?? date
        return Session(device: device, at: now, week: week(of: date, anchor: anchor, calendar: calendar), date: date)
    }

    public static func week(of date: Date, anchor: Date, calendar: Calendar) -> Int {
        let firstMonday = calendar.startOfWeek(containing: anchor)
        return max(1, calendar.dateComponents([.day], from: firstMonday, to: calendar.startOfDay(for: date)).day! / 7 + 1)
    }
}
