import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Observation

/// The sessions page and its rows. Times are judged against `now` when the page draws, not on a timer, except a
/// row's own under-way state, which its `LiveTime` passes in.
@MainActor @Observable
final class SessionsModel {
    var pending: PendingAction?
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
        let remaining = file.remainingClasses(after: now, planned: plan(now: now).map(\.draft))
        return ([String(localized: .sessionsCount(file.sessions.count))]
                + (remaining > 0 ? [String(localized: .sessionsRemaining(remaining))] : [])
                + (missing > 0 ? [String(localized: .sessionsMissingNotes(missing))] : [])).joined(separator: " · ")
    }

    /// `다음 시험 Quiz2 D-9`, in red after the subtitle: the one thing on the page with a deadline.
    func nextExam(_ file: CourseFile, now: Date? = nil) -> String? {
        let now = now ?? workspace.now
        guard let exam = file.exams.filter({ ($0.start ?? .distantPast) > now }).min(by: { $0.start! < $1.start! }),
              let days = examDays(exam, now: now) else { return nil }
        return String(localized: .sessionsNextExam(exam.title, days == 0 ? "D-day" : "D-\(days)"))
    }

    private func plan(now: Date) -> [Workspace.SuggestedSession] {
        workspace.course(courseId).map { workspace.plannedSessions(for: $0, now: now) } ?? []
    }

    struct TimelineRow: Identifiable {
        let item: SessionTimeline.Item
        /// For a planned class, what its menu acts on.
        var planned: Workspace.SuggestedSession?
        var id: String { item.id }
    }

    struct Week: Identifiable {
        let number: Int
        let start: Date
        let range: String
        let thisWeek: Bool
        let examWeek: Bool
        var rows: [TimelineRow]
        var id: String { "week-\(start.timeIntervalSinceReferenceDate)" }
    }

    /// The timeline cut into its weeks. An exam in a week with no class still gets the week it falls in, numbered from
    /// the term's start like the classes are.
    func weeks(_ file: CourseFile, now: Date? = nil) -> [Week] {
        let now = now ?? workspace.now
        let plan = plan(now: now)
        let byDate = Dictionary(plan.map { ($0.draft.date, $0) }, uniquingKeysWith: { a, _ in a })
        let semester = workspace.course(courseId).flatMap { workspace.semester(of: $0.file.course) }
        let anchor = semester?.start?.date(in: calendar) ?? file.sessions.map(\.date).min() ?? now
        let thisWeek = calendar.startOfWeek(containing: now)
        var weeks: [Week] = []
        func open(_ number: Int, _ date: Date) {
            let start = calendar.startOfWeek(containing: date)
            weeks.append(Week(number: number, start: start, range: range(from: start), thisWeek: start == thisWeek,
                              examWeek: semester?.examWeeks.contains(number) ?? false, rows: []))
        }
        for item in SessionTimeline.items(file, planned: plan.map(\.draft), classMinutes: workspace.settings.classMinutes, calendar: calendar) {
            switch item {
            case .week(let sessions, _):
                open(sessions[0].week, sessions[0].date)
            case .month:
                continue
            case .exam(_, let date):
                if weeks.last?.start != calendar.startOfWeek(containing: date) {
                    open(SessionPlanner.week(of: date, anchor: anchor, calendar: calendar), date)
                }
                weeks[weeks.count - 1].rows.append(TimelineRow(item: item))
            case .session:
                weeks[weeks.count - 1].rows.append(TimelineRow(item: item))
            case .planned(let s, _):
                weeks[weeks.count - 1].rows.append(TimelineRow(item: item, planned: byDate[s.date]))
            }
        }
        return weeks
    }

    /// `10월 19일 – 25일`, or `10월 26일 – 11월 1일` across a month.
    func range(from start: Date) -> String {
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        let sameMonth = calendar.component(.month, from: start) == calendar.component(.month, from: end)
        return start.formatted(.dateTime.month().day()) + " – " + end.formatted(sameMonth ? .dateTime.day() : .dateTime.month().day())
    }

    /// `화요일 오전 10:30 – 11:45`: the month and day are on the tile beside it. A date-only session (imported from
    /// Notion, stored at midnight) gives the weekday alone.
    func dayLine(_ date: Date, end: Date?) -> String {
        let weekday = date.formatted(.dateTime.weekday(.wide))
        let time = calendar.dateComponents([.hour, .minute], from: date)
        if time == DateComponents(hour: 0, minute: 0) && end == nil { return weekday }
        return weekday + " " + clock(date, end: end)
    }

    private func clock(_ start: Date, end: Date?) -> String {
        let minute = { (d: Date) in self.calendar.component(.hour, from: d) * 60 + self.calendar.component(.minute, from: d) }
        return end.map { TimeMenu.range(minute(start), minute($0)) } ?? TimeMenu.label(minute(start))
    }

    /// The marker's line: day and time, then where.
    func examLine(_ exam: Exam, _ date: Date) -> String {
        ([dayLine(date, end: exam.end)] + (exam.location.isEmpty ? [] : [exam.location])).joined(separator: " · ")
    }

    func month(_ date: Date) -> String { String(localized: .sessionsMonth(calendar.component(.month, from: date))) }
    func day(_ date: Date) -> String { String(calendar.component(.day, from: date)) }

    /// A planned class's second line: no session yet, so where it meets stands in for what it covered.
    func plannedLine(_ item: Workspace.SuggestedSession) -> String {
        ([dayLine(item.suggestion.date, end: item.suggestion.end)] + (item.suggestion.room.isEmpty ? [] : [item.suggestion.room])).joined(separator: " · ")
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
        workspace.importFiles(urls, into: CourseFolder.lectures.rawValue, session: session.id, course: courseId)
    }

    // MARK: Sessions made ahead

    /// Sessions made ahead when the app filled whole terms that nothing has used yet; listed for the user to delete.
    /// Reads the course's notes from disk, so the view loads it when the sessions change, not on every redraw.
    func loadUntouched(_ course: LoadedCourse, now: Date? = nil) {
        let now = now ?? workspace.now
        // Unreadable notes might point at any of them, so none is offered then.
        guard let notes = try? course.store.notes() else { untouched = []; return }
        untouched = course.file.untouchedFutureSessions(now: now, notedSessions: Set(notes.flatMap(\.meta.sessionIds)))
    }

    var untouchedShown: [Session] { Array(untouched.prefix(4)) }
    var untouchedMore: Int { untouched.count - untouchedShown.count }

    func removeUntouched() {
        pending = workspace.ask(SessionRemove(course: courseId, sessions: untouched.map(\.id)), button: .sessionsRemove)
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

    /// Only a class missed or late: present is the rule and says nothing.
    func lateMark(_ session: Session, in file: CourseFile) -> StepToggle<AttendanceState>.Option? {
        let attendance = menu.attendance(of: session)
        return session.isCancelled || attendance == .present ? nil : AttendanceState.steps.first { $0.value == attendance }
    }

    func isToday(_ date: Date) -> Bool { workspace.isStudyToday(date) }

    /// What the class covered, else just 수업, drawn quieter: the tile carries the date, so the week's own number
    /// (9주차-1) would only repeat it.
    func title(of session: Session, in file: CourseFile) -> String { file.subject(of: session) ?? String(localized: .sessionsClass) }

    func hasSubject(_ session: Session, in file: CourseFile) -> Bool { file.subject(of: session) != nil }

    /// Units that only restate the title (Lab04 Thin-layer chromatography under Thin-layer chromatography) shrink to their icon.
    func unitsInTitle(_ session: Session, in file: CourseFile) -> Bool {
        let units = UnitTree.deepest(file.units(of: session), in: file.units)
        return !units.isEmpty && units.allSatisfy {
            session.topic.isEmpty || $0.title.localizedCaseInsensitiveContains(session.topic) || session.topic.localizedCaseInsensitiveContains($0.title)
        }
    }

    enum Review: Equatable {
        case done(UUID), writing(UUID), missing
    }

    /// The review note's state as the card's pill says it; nil when there is nothing to say (ahead, cancelled, or a
    /// class that needs none).
    func review(of session: Session, in file: CourseFile, now: Date) -> Review? {
        if let id = session.reviewNoteId { return session.reviewNoteUnfinished ? .writing(id) : .done(id) }
        return file.needsReviewNote(session, at: now) ? .missing : nil
    }

    func recordingsLabel(_ count: Int) -> String {
        String(localized: count > 1 ? .sessionsRecordingCount(count) : .sessionsRecordingShort)
    }

    /// Only a class held, in a course with lecture files, has progress to record.
    func offersProgress(_ session: Session, in file: CourseFile) -> Bool { !session.isCancelled && !file.lectureFiles.isEmpty }

    // MARK: A session's actions

    /// The menu every screen shows for a class; the page adds playing, editing and deleting to it.
    var menu: SessionMenuModel { SessionMenuModel(workspace: workspace, courseId: courseId) }

    func remove(_ session: Session) {
        pending = workspace.ask(SessionRemove(course: courseId, sessions: [session.id]), button: .sessionsRemove)
    }
}
