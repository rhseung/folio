import Foundation

/// What a class's wrap-up asks about, in the order it asks. Announcements made in class (new assignments, exam dates)
/// are offered too but never missing: most classes have none.
public enum WrapUpItem: String, CaseIterable, Sendable {
    case progress, units, note, attendance
}

extension CourseFile {
    /// Whether the class's sheet is its wrap-up: the class is over, or a recording of it has stopped (`recorded`: one
    /// that just did and isn't saved yet). Before that the sheet is opened to link units, a note or the class's link
    /// ahead (2026-11-10). Real time, not the study day: the class ends at its own end.
    public func isWrappingUp(_ session: Session, recorded: Bool = false, at now: Date, classMinutes: Int, calendar: Calendar) -> Bool {
        recorded || recordings.contains { $0.sessionId == session.id }
            || session.isOver(at: now, schedule: course.schedule, classMinutes: classMinutes, calendar: calendar)
    }

    /// Saving the class's sheet counts as wrapping it up once the sheet is its wrap-up: every wrap-up field was there
    /// to see. A class still ahead or under way, or one that didn't happen, has nothing to wrap up yet; counting a
    /// save made during the class (to link its units) would stop the today card asking for its progress.
    public func savingWrapsUp(_ session: Session, at now: Date, classMinutes: Int, calendar: Calendar) -> Bool {
        !session.isCancelled && isWrappingUp(session, at: now, classMinutes: classMinutes, calendar: calendar)
    }

    /// What `session` has nothing for yet, in asking order. `recorded`: a recording of it has just stopped and isn't
    /// saved yet. Progress is asked only of a course with lecture files to go through.
    public func wrapUpGaps(of session: Session, recorded: Bool = false) -> [WrapUpItem] {
        let lectures = Set(lectureFiles.map(\.id))
        return WrapUpItem.allCases.filter { item in
            switch item {
            case .progress: !lectures.isEmpty && !session.materials.contains { lectures.contains($0.materialId) && $0.pages != nil }
            case .units: session.unitIds.isEmpty
            // A review note means the class was written up, whether or not notes were taken during it.
            case .note: session.roughNoteId == nil && session.reviewNoteId == nil
            // Present is stored as no entry, so it is known only from a recording, an entry, or a saved wrap-up.
            case .attendance: !attendanceKnown(of: session, recorded: recorded)
            }
        }
    }

    /// Attended for certain: someone recorded the class, or said how they attended.
    public func attendanceKnown(of session: Session, recorded: Bool = false) -> Bool {
        recorded || session.isWrappedUp || attendance.contains { $0.sessionId == session.id }
            || recordings.contains { $0.sessionId == session.id }
    }

    /// Classes the today screen asks to wrap up at `now`: ended, not cancelled, not wrapped up, with something missing,
    /// and only until the course's next class starts. After that the class is asked about from its menu only: a list
    /// that kept every class of the term would be ignored.
    public func classesToWrapUp(at now: Date, classMinutes: Int, calendar: Calendar) -> [Session] {
        sessions.filter { s in
            guard !s.isCancelled, !s.isWrappedUp,
                  s.expectedEnd(schedule: course.schedule, classMinutes: classMinutes, calendar: calendar) <= now else { return false }
            if let next = nextClassStart(after: s, calendar: calendar), next <= now { return false }
            return !wrapUpGaps(of: s).isEmpty
        }
        .sorted(by: Session.inOrder)
    }

    /// Classes of earlier study days still left to wrap up, oldest first: classes from before wrap-ups existed were
    /// never asked about, so their gaps are not choices. A saved wrap-up ends the question even with gaps left, since
    /// what it left empty was. Today's classes are the today card's and the recording prompt's until the day turns.
    public func unwrappedPastSessions(at now: Date, settings: Settings, calendar: Calendar) -> [Session] {
        sessions.filter { isLeftUnwrapped($0, at: now, settings: settings, calendar: calendar) }.sorted(by: Session.inOrder)
    }

    public func isLeftUnwrapped(_ s: Session, at now: Date, settings: Settings, calendar: Calendar) -> Bool {
        !s.isCancelled && !s.isWrappedUp
            && settings.studyDay(of: s.date, calendar: calendar) < settings.studyDay(of: now, calendar: calendar)
            && !wrapUpGaps(of: s).isEmpty
    }

    /// When the course meets next after `session`: its next session that isn't cancelled, or the next weekly class
    /// no cancelled session stands for, whichever is sooner. Nil for a course with neither.
    public func nextClassStart(after session: Session, calendar: Calendar) -> Date? {
        let later = sessions.filter { !$0.isCancelled && $0.date > session.date }
            .map(\.date).min()
        let cancelled = Set(sessions.filter(\.isCancelled).map(\.date))
        let slot = Self.nextSlot(in: course.schedule, after: session.date, skipping: cancelled, calendar: calendar)
        return [later, slot].compactMap { $0 }.min()
    }

    /// The first weekly class starting after `date`, two weeks ahead at most, other than those at `skipping`.
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

    /// The notes a wrap-up offers as a class's note, newest first: those no class holds yet. A review note is written
    /// after its classes and an exam's note is the exam's, so neither is offered.
    public var classNoteChoices: [NoteEntry] {
        let taken = Set(sessions.flatMap { [$0.roughNoteId, $0.reviewNoteId].compactMap { $0 } })
        return notes.filter { !taken.contains($0.id) && $0.kind != .review && $0.examId == nil }
            .sorted { $0.createdAt > $1.createdAt }
    }
}

extension Session {
    /// Whether the sheet starts a suggested range checked. A file the class already links that nothing gives both
    /// ends for keeps its link as it is: checked, it would hold the save until an end is picked, for a class that
    /// linked the file whole on purpose. Unchecked leaves a link alone, so saving with it unchecked writes nothing.
    /// Until the class is wrapped up (`CourseFile.isWrappingUp`) only the pages it has saved start checked
    /// (2026-11-10): the sheet is opened then to link units or a note ahead, and a suggestion checked would hold that
    /// save until an end the class hasn't reached is picked, or write pages it is still going through.
    public func wrapUpChecks(_ range: SessionMaterial, wrappingUp: Bool) -> Bool {
        guard wrappingUp else { return range.firstPage != nil && range.lastPage != nil && materials.contains(range) }
        return (range.firstPage != nil && range.lastPage != nil) || !materials.contains { $0.materialId == range.materialId }
    }

    /// The ranges among `ranges` the class doesn't have yet. The wrap-up shows every class's current pages, so a
    /// save writes only what was changed or newly suggested.
    public func changedRanges(_ ranges: [SessionMaterial]) -> [SessionMaterial] {
        ranges.filter { r in
            guard let had = materials.first(where: { $0.materialId == r.materialId }) else { return true }
            return had.firstPage != r.firstPage || had.lastPage != r.lastPage
        }
    }
}
