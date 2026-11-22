import Foundation

extension CourseFile {
    public func isWrappingUp(_ session: Session, recorded: Bool = false, at now: Date, classMinutes: Int, calendar: Calendar) -> Bool {
        recorded || recordings.contains { $0.sessionId == session.id }
            || session.isOver(at: now, schedule: course.schedule, classMinutes: classMinutes, calendar: calendar)
    }

    // 수업 중에 단원을 연결하려고 저장한 것까지 정리로 세면, 오늘 화면의 카드가 그 수업의 진도를 더는 묻지 않는다.
    public func savingWrapsUp(_ session: Session, recorded: Bool = false, at now: Date, classMinutes: Int, calendar: Calendar) -> Bool {
        !session.isCancelled && isWrappingUp(session, recorded: recorded, at: now, classMinutes: classMinutes, calendar: calendar)
    }

    public func wrapUpGaps(of session: Session, recorded: Bool = false) -> [WrapUpItem] {
        wrapUpGaps(of: session, recorded: recorded, outline: UnitTree.outline(units).map(\.unit), lectures: Set(lectureFiles.map(\.id)))
    }

    // 단원 순서와 렉처 파일은 부르는 쪽이 한 번 만들어 넘긴다. 회차마다 만들면 회차 표 하나에 단원 순서를 회차 수만큼 만들고
    // 렉처 파일을 그만큼 경로로 정렬한다.
    func wrapUpGaps(of session: Session, recorded: Bool = false, outline: [Unit], lectures: Set<UUID>) -> [WrapUpItem] {
        WrapUpItem.allCases.filter { item in
            switch item {
            case .progress: !lectures.isEmpty && !session.materials.contains { lectures.contains($0.materialId) && $0.pages != nil }
            case .units: unitIds(of: session, outline: outline).isEmpty
            case .note: session.roughNoteId == nil && session.reviewNoteId == nil
            // 출석은 기록이 없는 것으로 저장하므로, 녹음이나 출결 기록, 저장한 정리로만 알 수 있다.
            case .attendance: !attendanceKnown(of: session, recorded: recorded)
            }
        }
    }

    public func attendanceKnown(of session: Session, recorded: Bool = false) -> Bool {
        recorded || session.isWrappedUp || attendance.contains { $0.sessionId == session.id }
            || recordings.contains { $0.sessionId == session.id }
    }

    public func classesToWrapUp(at now: Date, classMinutes: Int, calendar: Calendar) -> [Session] {
        let outline = UnitTree.outline(units).map(\.unit)
        let lectures = Set(lectureFiles.map(\.id))
        return sessions.filter { s in
            guard !s.isCancelled, !s.isWrappedUp,
                s.expectedEnd(schedule: course.schedule, classMinutes: classMinutes, calendar: calendar) <= now
            else { return false }
            if let next = nextClassStart(after: s, calendar: calendar), next <= now { return false }
            return !wrapUpGaps(of: s, outline: outline, lectures: lectures).isEmpty
        }
        .sorted(by: Session.inOrder)
    }

    public func unwrappedPastSessions(at now: Date, settings: Settings, calendar: Calendar) -> [Session] {
        leftUnwrapped(at: now, settings: settings, calendar: calendar).map(\.session)
    }

    // 정리하지 않은 지난 수업과 그 수업에 빠진 것을 함께 구한다. 카드가 줄마다 빠진 것을 다시 구하지 않게 한다.
    public func leftUnwrapped(at now: Date, settings: Settings, calendar: Calendar) -> [(session: Session, gaps: [WrapUpItem])] {
        let outline = UnitTree.outline(units).map(\.unit)
        let lectures = Set(lectureFiles.map(\.id))
        let today = settings.studyDay(of: now, calendar: calendar)
        return sessions.sorted(by: Session.inOrder).compactMap { s in
            guard !s.isCancelled, !s.isWrappedUp, settings.studyDay(of: s.date, calendar: calendar) < today else { return nil }
            let gaps = wrapUpGaps(of: s, outline: outline, lectures: lectures)
            return gaps.isEmpty ? nil : (s, gaps)
        }
    }

    public func isLeftUnwrapped(_ s: Session, at now: Date, settings: Settings, calendar: Calendar) -> Bool {
        !s.isCancelled && !s.isWrappedUp
            && settings.studyDay(of: s.date, calendar: calendar) < settings.studyDay(of: now, calendar: calendar)
            && !wrapUpGaps(of: s).isEmpty
    }

    public func nextClassStart(after session: Session, calendar: Calendar) -> Date? {
        let later = sessions.filter { !$0.isCancelled && $0.date > session.date }
            .map(\.date).min()
        let cancelled = Set(sessions.filter(\.isCancelled).map(\.date))
        let slot = Self.nextSlot(in: course.schedule, after: session.date, skipping: cancelled, calendar: calendar)
        return [later, slot].compactMap { $0 }.min()
    }

    static func nextSlot(in schedule: [ClassTime], after date: Date, skipping: Set<Date>, calendar: Calendar) -> Date? {
        guard !schedule.isEmpty else { return nil }
        let day = calendar.startOfDay(for: date)
        for offset in 0..<15 {
            guard let d = calendar.date(byAdding: .day, value: offset, to: day) else { continue }
            let weekday = calendar.isoWeekday(of: d)
            let starts = schedule.filter { $0.weekday == weekday }.map(\.startMinute).sorted()
                .compactMap { calendar.date(byAdding: .minute, value: $0, to: d) }
                .filter { $0 > date && !skipping.contains($0) }
            if let first = starts.first { return first }
        }
        return nil
    }

    public var classNoteChoices: [NoteEntry] {
        let taken = Set(sessions.flatMap { [$0.roughNoteId, $0.reviewNoteId].compactMap { $0 } })
        return notes.filter { !taken.contains($0.id) && $0.kind != .review && $0.examId == nil }
            .sorted { $0.createdAt > $1.createdAt }
    }
}

extension Session {
    public func wrapUpChecks(_ range: SessionMaterial, wrappingUp: Bool) -> Bool {
        guard wrappingUp else { return range.firstPage != nil && range.lastPage != nil && materials.contains(range) }
        return (range.firstPage != nil && range.lastPage != nil) || !materials.contains { $0.materialId == range.materialId }
    }

    public func changedRanges(_ ranges: [SessionMaterial]) -> [SessionMaterial] {
        ranges.filter { r in
            guard let had = materials.first(where: { $0.materialId == r.materialId }) else { return true }
            return had.firstPage != r.firstPage || had.lastPage != r.lastPage
        }
    }

    // 처음에 꺼진 행(그대로 둔 파일 전체 연결, 수업 중의 제안)은 어떻게 두든 아무것도 쓰지 않는다. 그렇지 않으면
    // 시트를 열고 저장만 해도 아무도 건드리지 않은 연결이 사라진다.
    public func droppedLinks(started: Set<UUID>, kept: Set<UUID>) -> [UUID] {
        materials.map(\.materialId).filter { started.contains($0) && !kept.contains($0) }
    }
}
