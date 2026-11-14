import Foundation

public enum SessionTimeline {
    public enum Item: Identifiable, Sendable {
        case week([Session], month: Date?)
        case month(Date)
        case exam(Exam, Date)
        case session(Session, exams: [Exam])
        case planned(Session, exams: [Exam])

        public var id: String {
            switch self {
            case .week(let s, _): "week-\(s[0].week)"
            case .month(let d): "month-\(d.timeIntervalSinceReferenceDate)"
            case .exam(let e, _): "exam-\(e.id)"
            case .session(let s, _): s.id.uuidString
            case .planned(let s, _): "planned-\(s.date.timeIntervalSinceReferenceDate)"
            }
        }

        public var date: Date {
            switch self {
            case .week(let s, _): s[0].date
            case .month(let d), .exam(_, let d): d
            case .session(let s, _), .planned(let s, _): s.date
            }
        }

        public func held(at now: Date) -> Bool { date <= now }
    }

    public static func items(_ file: CourseFile, planned: [Session] = [], classMinutes: Int, calendar: Calendar) -> [Item] {
        let plannedIds = Set(planned.map(\.id))
        let weeks = Dictionary(grouping: file.sessions + planned, by: \.week).sorted { $0.key < $1.key }.map {
            $0.value.sorted(by: Session.inOrder)
        }
        let dated = file.exams.compactMap { e in e.start.map { (exam: e, date: $0) } }.sorted { $0.date < $1.date }

        var onClass: [UUID: [Exam]] = [:]
        var free: [(exam: Exam, date: Date)] = []
        let classes = (file.sessions + planned).filter { !$0.isCancelled }.sorted(by: Session.inOrder)
        for e in dated {
            let end = max(e.exam.end ?? e.date, e.date)
            if let s = classes.first(where: {
                $0.date <= end && e.date < $0.expectedEnd(schedule: file.course.schedule, classMinutes: classMinutes, calendar: calendar)
            }) {
                onClass[s.id, default: []].append(e.exam)
            } else {
                free.append(e)
            }
        }

        var items: [Item] = []
        var month: Int?
        func opens(_ date: Date) -> Bool {
            let m = calendar.component(.year, from: date) * 12 + calendar.component(.month, from: date)
            defer { month = m }
            return m != month
        }
        func exam(_ e: (exam: Exam, date: Date)) -> Item { .exam(e.exam, e.date) }

        var pending = free[...]
        for sessions in weeks {
            let week = calendar.startOfWeek(containing: sessions[0].date)
            while let e = pending.first, calendar.startOfWeek(containing: e.date) < week { items.append(exam(e)); pending.removeFirst() }
            var rows: [(date: Date, item: Item)] = sessions.map { s in
                let exams = onClass[s.id] ?? []
                return (s.date, plannedIds.contains(s.id) ? .planned(s, exams: exams) : .session(s, exams: exams))
            }
            while let e = pending.first, calendar.startOfWeek(containing: e.date) == week {
                rows.append((e.date, exam(e))); pending.removeFirst()
            }
            // `sort`는 안정 정렬이 아니므로, 같은 값은 인덱스로 순서를 정해 `Session.inOrder`의 순서를 지킨다.
            rows = rows.enumerated().sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }.map(\.element)
            items.append(.week(sessions, month: opens(rows[0].date) ? rows[0].date : nil))
            for (i, row) in rows.enumerated() {
                if i > 0 && opens(row.date) { items.append(.month(row.date)) }
                items.append(row.item)
            }
        }
        return items + pending.map(exam)
    }
}

extension CourseFile {
    public func missingReviewNotes(at now: Date) -> Int {
        sessions.filter { needsReviewNote($0, at: now) }.count
    }

    public func remainingClasses(after now: Date, planned: [Session]) -> Int {
        sessions.filter { $0.date > now && !$0.isCancelled }.count + planned.filter { $0.date > now && !$0.isCancelled }.count
    }

    public func sessionsNeedingUnits(at now: Date) -> [Session] {
        units.isEmpty ? [] : sessions.filter { needsUnits($0, at: now) }.sorted { $0.date > $1.date }
    }
}
