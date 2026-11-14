import Foundation

extension Exam {
    // 날이 바뀔 때가 아니라 시험이 끝났을 때 지난 것으로 본다. 오늘 아침에 끝난 시험은 다가오는 시험이 아니다.
    public func isOver(now: Date, today: LocalDate, calendar: Calendar) -> Bool {
        if let end { return end < now }
        return start.map { LocalDate($0, in: calendar) < today } ?? false
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
