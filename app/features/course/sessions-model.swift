import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Observation

/// The sessions page and its rows. Times are judged against `now` when the page draws, not on a timer, except a
/// row's own under-way state, which its TimelineView passes in.
@MainActor @Observable
final class SessionsModel {
    let workspace: Workspace
    let courseId: UUID
    private(set) var untouched: [Session] = []

    init(workspace: Workspace, courseId: UUID) {
        self.workspace = workspace
        self.courseId = courseId
    }

    var calendar: Calendar { workspace.calendar }

    func subtitle(_ file: CourseFile, now: Date? = nil) -> String {
        let now = now ?? workspace.now
        guard !file.sessions.isEmpty else { return String(localized: .sessionsEmpty) }
        let missing = file.missingReviewNotes(at: now)
        let unlinked = file.sessionsNeedingUnits(at: now).count
        return ([String(localized: .sessionsCount(file.sessions.count))]
                + (missing > 0 ? [String(localized: .sessionsMissingNotes(missing))] : [])
                + (unlinked > 0 ? [String(localized: .sessionsMissingUnits(unlinked))] : [])).joined(separator: " · ")
    }

    struct TimelineRow: Identifiable {
        let item: SessionTimeline.Item
        /// For a planned class, what its menu acts on.
        var planned: Workspace.SuggestedSession?
        let first: Bool
        /// The rail above and below the line's dot: nil at the ends, true once held.
        let above: Bool?
        let below: Bool?
        var id: String { item.id }
    }

    func timeline(_ file: CourseFile, now: Date? = nil) -> [TimelineRow] {
        let now = now ?? workspace.now
        let plan = workspace.course(courseId).map { workspace.plannedSessions(for: $0, now: now) } ?? []
        let byDate = Dictionary(plan.map { ($0.draft.date, $0) }, uniquingKeysWith: { a, _ in a })
        let items = SessionTimeline.items(file, planned: plan.map(\.draft), classMinutes: workspace.settings.classMinutes, calendar: calendar)
        return items.indices.map { i in
            var planned: Workspace.SuggestedSession?
            if case .planned(let s, _) = items[i] { planned = byDate[s.date] }
            return TimelineRow(item: items[i], planned: planned, first: i == 0, above: i == 0 ? nil : items[i].held(at: now),
                               below: i == items.count - 1 ? nil : items[i + 1].held(at: now))
        }
    }

    /// `14일 후 오전 10:30 · 203`: the day is in the gutter.
    func plannedLine(_ item: Workspace.SuggestedSession, now: Date? = nil) -> String {
        let date = item.suggestion.date
        let clock = TimeMenu.label(calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date))
        return Self.ahead(date, clock: clock, now: now ?? workspace.now, calendar: calendar) + (item.suggestion.room.isEmpty ? "" : " · \(item.suggestion.room)")
    }

    func isThisWeek(_ date: Date) -> Bool { calendar.startOfWeek(containing: date) == calendar.startOfWeek(containing: workspace.now) }

    func examLine(_ exam: Exam, _ date: Date) -> String {
        ([exam.title, date.formatted(.dateTime.month().day().weekday())] + (examTime(exam).map { [$0] } ?? [])).joined(separator: " · ")
    }

    func examTime(_ exam: Exam) -> String? {
        guard let start = exam.start else { return nil }
        let minute = { (d: Date) in self.calendar.component(.hour, from: d) * 60 + self.calendar.component(.minute, from: d) }
        return exam.end.map { TimeMenu.range(minute(start), minute($0)) } ?? TimeMenu.label(minute(start))
    }

    /// Days left only while the exam is ahead. A past one keeps its red but says nothing more: its score is a grade
    /// and stays on the grades page.
    func examDays(_ exam: Exam, now: Date) -> Int? {
        exam.start.flatMap { $0 > now ? max(workspace.days(to: $0), 0) : nil }
    }

    func end(of session: Session, in file: CourseFile) -> Date? { session.end(schedule: file.course.schedule, calendar: calendar) }

    func link(of session: Session, in file: CourseFile) -> URL? { session.link(schedule: file.course.schedule, calendar: calendar) }

    /// The join button stands out only around the class: from the study day it falls on until it ends. Before and
    /// after, the link stays in the menu.
    func offersJoin(_ session: Session, in file: CourseFile, now: Date) -> Bool {
        !session.isCancelled && isToday(session.date)
            && now < session.expectedEnd(schedule: file.course.schedule, classMinutes: workspace.settings.classMinutes, calendar: calendar)
    }

    func importFiles(_ urls: [URL], into session: Session) {
        workspace.importFiles(urls, into: CourseFolder.lectures.rawValue, week: session.week, session: session.id, course: courseId)
    }

    // MARK: Sessions made ahead

    /// Sessions made ahead when the app filled whole terms that nothing has used yet; listed for the user to delete.
    /// Reads the course's notes from disk, so the view loads it when the sessions change, not on every redraw.
    func loadUntouched(_ course: LoadedCourse, now: Date? = nil) {
        let now = now ?? workspace.now
        // Unreadable notes might point at any of them, so none is offered then.
        guard let notes = try? course.store.notes() else { untouched = []; return }
        untouched = course.file.untouchedFutureSessions(now: now, notedSessions: Set(notes.compactMap(\.meta.sessionId)))
    }

    var untouchedShown: [Session] { Array(untouched.prefix(4)) }
    var untouchedMore: Int { untouched.count - untouchedShown.count }

    func removeUntouched() {
        workspace.run(SessionRemove(course: courseId, sessions: untouched.map(\.id)))
    }

    // MARK: A session's row

    func isOngoing(_ session: Session, end: Date?, now: Date) -> Bool {
        !session.isCancelled && end.map { now >= session.date && now < $0 } ?? false
    }

    /// How far the class under way has gone, for the dot's ring; nil when it isn't under way.
    func progress(_ session: Session, end: Date?, now: Date) -> Double? {
        guard isOngoing(session, end: end, now: now), let end else { return nil }
        return now.timeIntervalSince(session.date) / end.timeIntervalSince(session.date)
    }

    func minutesLeft(until end: Date, now: Date) -> String {
        String(localized: .sessionsMinutesLeft(Int(end.timeIntervalSince(now) / 60) + 1))
    }

    func recordings(of session: Session, in file: CourseFile) -> [Recording] { file.recordings.filter { $0.sessionId == session.id } }

    func attendance(of session: Session, in file: CourseFile) -> AttendanceState {
        file.attendance.first { $0.sessionId == session.id }?.state ?? .present
    }

    /// Only a class missed or late: present is the rule and says nothing.
    func lateMark(_ session: Session, in file: CourseFile) -> StepToggle<AttendanceState>.Option? {
        let attendance = attendance(of: session, in: file)
        return session.isCancelled || attendance == .present ? nil : AttendanceState.steps.first { $0.value == attendance }
    }

    func isToday(_ date: Date) -> Bool { workspace.isStudyToday(date) }

    /// The title says what the class covered, else its name (9주차-1): the day is in the gutter beside it. The kind
    /// (실험) is left out: a lab is a class like any other.
    func title(of session: Session, in file: CourseFile) -> String { file.subject(of: session) ?? file.name(of: session) }

    /// Units that only restate the title (Lab04 Thin-layer chromatography under Thin-layer chromatography) shrink to their icon.
    func unitsInTitle(_ session: Session, in file: CourseFile) -> Bool {
        let units = UnitTree.deepest(file.units(of: session), in: file.units)
        return !units.isEmpty && units.allSatisfy {
            session.topic.isEmpty || $0.title.localizedCaseInsensitiveContains(session.topic) || session.topic.localizedCaseInsensitiveContains($0.title)
        }
    }

    /// The date and weekday are in the gutter, so the line under the title carries only the time and how far off.
    func when(_ session: Session, now: Date) -> String? {
        // Sessions imported from Notion carry a date only, stored at midnight.
        let time = calendar.dateComponents([.hour, .minute], from: session.date)
        let clock = time == DateComponents(hour: 0, minute: 0) ? "" : TimeMenu.label((time.hour ?? 0) * 60 + (time.minute ?? 0))
        if session.date > now { return Self.ahead(session.date, clock: clock, now: now, calendar: calendar) }
        return clock.isEmpty ? nil : clock
    }

    static func ahead(_ date: Date, clock: String, now: Date, calendar: Calendar) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: return String(localized: .sessionsTodayAt(clock))
        case 1: return String(localized: .sessionsTomorrowAt(clock))
        // The gutter shows only the day, so the start time stays in the line.
        default: return clock.isEmpty ? String(localized: .sessionsDaysLater(days)) : String(localized: .sessionsDaysLaterAt(days, clock))
        }
    }

    func recordingsLabel(_ count: Int) -> String {
        String(localized: count > 1 ? .sessionsRecordingCount(count) : .sessionsRecordingShort)
    }

    func playLabel(_ index: Int, _ recording: Recording) -> String {
        String(localized: .sessionsPlayRecording(index + 1, RecordingTime.label(recording.duration)))
    }

    func playerTitle(_ session: Session, in file: CourseFile) -> String { "\(file.course.title) · \(file.title(of: session, calendar: calendar))" }

    func removeConfirmation(_ session: Session, in file: CourseFile) -> String {
        String(localized: .sessionsRemoveConfirm(file.day(of: session, calendar: calendar)))
    }

    // MARK: A session's actions

    func takesAttendance(_ session: Session) -> Bool {
        workspace.can(AttendanceSet(course: courseId, session: session.id, state: .absent))
    }

    func setAttendance(_ state: AttendanceState, of session: Session) {
        workspace.run(AttendanceSet(course: courseId, session: session.id, state: state))
    }

    func setCancelled(_ cancelled: Bool, of session: Session) {
        workspace.run(SessionSet(course: courseId, session: session.id, cancelled: .set(cancelled)))
    }

    func setSkipsReview(_ skips: Bool, of session: Session) { workspace.setSkipsReview(skips, of: session.id, in: courseId) }

    func record(_ session: Session) { workspace.record(session.id, in: courseId) }

    func note(_ kind: NoteKind, of session: Session) -> UUID? { workspace.note(kind, of: session.id, in: courseId) }

    /// Why the session can't be deleted, or nil when it can.
    func removalRefusal(_ session: Session) -> String? { workspace.refusal(SessionRemove(course: courseId, sessions: [session.id])) }

    func remove(_ session: Session) { workspace.run(SessionRemove(course: courseId, sessions: [session.id])) }
}
