import Foundation

extension Exam {
    // 날이 바뀔 때가 아니라 시험이 끝났을 때 지난 것으로 본다. 오늘 아침에 끝난 시험은 다가오는 시험이 아니다.
    public func isOver(now: Date, today: LocalDate, calendar: Calendar) -> Bool {
        if let end { return end < now }
        return start.map { LocalDate($0, in: calendar) < today } ?? false
    }
}

public enum AssignmentGroup: CaseIterable, Sendable {
    case overdue, open, submitted, graded

    public init(_ a: Assignment, now: Date) {
        switch a.status {
        case .graded: self = .graded
        case .submitted: self = .submitted
        case .todo, .doing: self = (a.due.map { $0 < now } ?? false) ? .overdue : .open
        }
    }

    public func sorted(_ items: [Assignment]) -> [Assignment] {
        switch self {
        case .overdue, .open: items.sorted { ($0.due ?? .distantFuture, $0.title) < ($1.due ?? .distantFuture, $1.title) }
        case .submitted, .graded: items.sorted { ($0.due ?? .distantPast, $0.title) > ($1.due ?? .distantPast, $1.title) }
        }
    }
}

public enum NoteGroup: CaseIterable, Sendable {
    case classes, exams, units, free

    public init(_ kind: NoteKind) {
        switch kind {
        case .rough, .review: self = .classes
        case .examSummary: self = .exams
        case .unit: self = .units
        case .free: self = .free
        }
    }

    public static func grouped<Note>(
        _ notes: [Note], meta: (Note) -> NoteMeta, title: (Note) -> String,
        in file: CourseFile
    ) -> [(group: NoteGroup, notes: [Note])] {
        allCases.compactMap { group in
            let members = notes.filter { NoteGroup(meta($0).kind) == group }
            return members.isEmpty ? nil : (group, group.sorted(members, meta: meta, title: title, in: file))
        }
    }

    public func sorted<Note>(_ notes: [Note], meta: (Note) -> NoteMeta, title: (Note) -> String, in file: CourseFile) -> [Note] {
        func byTitle(_ a: Note, _ b: Note) -> Bool { title(a).localizedStandardCompare(title(b)) == .orderedAscending }

        switch self {
        case .classes:
            let keyed = notes.map { (note: $0, kind: meta($0).kind, last: file.sessions(pointingAt: meta($0).id).last) }
            return keyed.sorted { a, b in
                switch (a.last, b.last) {
                case let (x?, y?) where x.id != y.id: x.date > y.date
                case (_?, nil): true
                case (nil, _?): false
                default: a.kind == b.kind ? byTitle(a.note, b.note) : a.kind == .rough
                }
            }.map(\.note)
        case .exams:
            let keyed = notes.map { n in (note: n, start: file.exams.first { $0.id == meta(n).examId }?.start ?? .distantFuture) }
            return keyed.sorted { a, b in a.start != b.start ? a.start < b.start : byTitle(a.note, b.note) }.map(\.note)
        case .units, .free:
            return notes.sorted(by: byTitle)
        }
    }
}

extension CourseFile {
    public func sessions(pointingAt note: UUID?) -> [Session] {
        guard let note else { return [] }
        return sessions.filter { $0.roughNoteId == note || $0.reviewNoteId == note }.sorted(by: Session.inOrder)
    }

    public func sessionSpan(of note: UUID?, calendar: Calendar) -> String? {
        let linked = sessions(pointingAt: note)
        guard let first = linked.first, let last = linked.last else { return nil }
        let day = { (s: Session) in self.day(of: s, calendar: calendar) }
        return first.id == last.id ? day(first) : String(localized: .sessionSpan(day(first), day(last)))
    }

    // `order`는 형제 사이의 순서일 뿐이라서, 이 값만으로 정렬하면 장과 그 아래 단원이 뒤섞인다.
    public func units(of note: NoteMeta) -> [Unit] {
        UnitTree.outline(units).map(\.unit).filter { note.unitIds.contains($0.id) }
    }
}

extension ReviewState {
    public func isOnTrack(today: LocalDate) -> Bool {
        !writeNoteFirst && (due.map { $0 >= today } ?? true)
    }
}
