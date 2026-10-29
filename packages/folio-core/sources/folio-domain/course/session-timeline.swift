import Foundation

/// The course's sessions read down one timeline: each week, its sessions in date order, the midterm and final where
/// they fall, and a month marker wherever the month turns (the timeline shows only the day).
public enum SessionTimeline {
    public enum Item: Identifiable, Sendable {
        /// With the month when the week opens one.
        case week([Session], month: Date?)
        /// A month that begins partway through a week.
        case month(Date)
        case exam(Exam, Date)
        case session(Session)

        public var id: String {
            switch self {
            case .week(let s, _): "week-\(s[0].week)"
            case .month(let d): "month-\(d.timeIntervalSinceReferenceDate)"
            case .exam(let e, _): "exam-\(e.id)"
            case .session(let s): s.id.uuidString
            }
        }

        public var date: Date {
            switch self {
            case .week(let s, _): s[0].date
            case .month(let d), .exam(_, let d): d
            case .session(let s): s.date
            }
        }

        public func held(at now: Date) -> Bool { date <= now }
    }

    public static func items(_ file: CourseFile, calendar: Calendar) -> [Item] {
        let weeks = Dictionary(grouping: file.sessions, by: \.week).sorted { $0.key < $1.key }.map { $0.value.sorted { $0.date < $1.date } }
        // Quizzes and the rest are many and small; only the two big exams mark the term.
        let exams = file.exams.filter { $0.kind == .midterm || $0.kind == .final }
            .compactMap { e in e.start.map { (exam: e, date: $0) } }.sorted { $0.date < $1.date }
        var items: [Item] = []
        var after = Date.distantPast
        var month: Int?
        func opens(_ date: Date) -> Bool {
            let m = calendar.component(.year, from: date) * 12 + calendar.component(.month, from: date)
            defer { month = m }
            return m != month
        }
        for sessions in weeks {
            items += exams.filter { $0.date > after && $0.date <= sessions[0].date }.map { .exam($0.exam, $0.date) }
            items.append(.week(sessions, month: opens(sessions[0].date) ? sessions[0].date : nil))
            for (i, s) in sessions.enumerated() {
                if i > 0 && opens(s.date) { items.append(.month(s.date)) }
                items.append(.session(s))
            }
            after = sessions.last!.date
        }
        return items + exams.filter { $0.date > after }.map { .exam($0.exam, $0.date) }
    }
}

extension CourseFile {
    /// Past classes still owing their review note, the count the sessions page warns with.
    public func missingReviewNotes(at now: Date) -> Int {
        sessions.filter { needsReviewNote($0, at: now) }.count
    }

    /// Held classes no unit covers, newest first. None while the course has no units: there is nothing to link yet.
    public func sessionsNeedingUnits(at now: Date) -> [Session] {
        units.isEmpty ? [] : sessions.filter { needsUnits($0, at: now) }.sorted { $0.date > $1.date }
    }
}
