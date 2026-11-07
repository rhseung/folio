import Foundation

/// What a class's wrap-up asks about, in the order it asks. Announcements made in class (new assignments, exam dates)
/// are offered too but never missing: most classes have none.
public enum WrapUpItem: String, CaseIterable, Sendable {
    case progress, units, topic, note, attendance
}

extension CourseFile {
    /// What `session` has nothing for yet, in asking order. `recorded`: a recording of it has just stopped and isn't
    /// saved yet. Progress is asked only of a course with lecture files to go through.
    public func wrapUpGaps(of session: Session, recorded: Bool = false) -> [WrapUpItem] {
        let lectures = Set(lectureFiles.map(\.id))
        return WrapUpItem.allCases.filter { item in
            switch item {
            case .progress: !lectures.isEmpty && !session.materials.contains { lectures.contains($0.materialId) && $0.pages != nil }
            case .units: session.unitIds.isEmpty
            case .topic: session.topic.trimmingCharacters(in: .whitespaces).isEmpty
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

    /// The units a wrap-up lists first: those of the class before, which a class most often carries on with. Only
    /// listed first, not chosen: whether a unit is finished is the user's call.
    public func recentUnits(before session: Session) -> [UUID] {
        sessions.filter { !$0.isCancelled && $0.id != session.id && Session.inOrder($0, session) && !$0.unitIds.isEmpty }
            .max(by: Session.inOrder)?.unitIds ?? []
    }
}
