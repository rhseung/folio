import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Observation

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
        return
            ([String(localized: .sessionsCount(file.sessions.count))]
            + (remaining > 0 ? [String(localized: .sessionsRemaining(remaining))] : [])
            + (missing > 0 ? [String(localized: .sessionsMissingNotes(missing))] : [])).joined(separator: " · ")
    }

    func nextExam(_ file: CourseFile, now: Date? = nil) -> String? {
        let now = now ?? workspace.now
        guard let exam = file.exams.filter({ ($0.start ?? .distantPast) > now }).min(by: { $0.start! < $1.start! }),
            let days = examDays(exam, now: now)
        else { return nil }
        return String(localized: .sessionsNextExam(exam.title, days == 0 ? "D-day" : "D-\(days)"))
    }

    private func plan(now: Date) -> [Workspace.SuggestedSession] {
        workspace.course(courseId).map { workspace.plannedSessions(for: $0, now: now) } ?? []
    }

    struct TimelineRow: Identifiable {
        let item: SessionTimeline.Item
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
            weeks.append(
                Week(
                    number: number, start: start, range: range(from: start), thisWeek: start == thisWeek,
                    examWeek: semester?.examWeeks.contains(number) ?? false, rows: []))
        }

        for item in SessionTimeline.items(
            file, planned: plan.map(\.draft), classMinutes: workspace.settings.classMinutes, calendar: calendar)
        {
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

    func range(from start: Date) -> String {
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        let sameMonth = calendar.component(.month, from: start) == calendar.component(.month, from: end)
        return start.formatted(.dateTime.month().day()) + " – " + end.formatted(sameMonth ? .dateTime.day() : .dateTime.month().day())
    }

    func dayLine(_ date: Date, end: Date?) -> String {
        let weekday = date.formatted(.dateTime.weekday(.wide))
        let time = calendar.dateComponents([.hour, .minute], from: date)
        if time == DateComponents(hour: 0, minute: 0) && end == nil { return weekday }
        return weekday + " " + clock(date, end: end)
    }

    private func clock(_ start: Date, end: Date?) -> String {
        let minute = { (d: Date) in Self.minute(of: d, in: self.calendar) }
        return end.map { TimeMenu.range(minute(start), minute($0)) } ?? TimeMenu.label(minute(start))
    }

    static func minute(of date: Date, in calendar: Calendar) -> Int {
        calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }

    static func weekdayTime(_ date: Date, in calendar: Calendar) -> String {
        date.formatted(.dateTime.weekday()) + " " + TimeMenu.label(minute(of: date, in: calendar))
    }

    func examLine(_ exam: Exam, _ date: Date) -> String {
        ([dayLine(date, end: exam.end)] + (exam.location.isEmpty ? [] : [exam.location])).joined(separator: " · ")
    }

    func month(_ date: Date) -> String { String(localized: .sessionsMonth(calendar.component(.month, from: date))) }
    func day(_ date: Date) -> String { String(calendar.component(.day, from: date)) }

    func plannedLine(_ item: Workspace.SuggestedSession) -> String {
        ([dayLine(item.suggestion.date, end: item.suggestion.end)] + (item.suggestion.room.isEmpty ? [] : [item.suggestion.room])).joined(
            separator: " · ")
    }

    func examTime(_ exam: Exam) -> String? {
        exam.start.map { clock($0, end: exam.end) }
    }

    func examDays(_ exam: Exam, now: Date) -> Int? {
        exam.start.flatMap { $0 > now ? max(workspace.days(to: $0), 0) : nil }
    }

    func end(of session: Session, in file: CourseFile) -> Date? { session.end(schedule: file.course.schedule, calendar: calendar) }

    func link(of session: Session, in file: CourseFile) -> URL? { session.link(schedule: file.course.schedule, calendar: calendar) }

    func offersJoin(_ session: Session, in file: CourseFile, now: Date) -> Bool {
        !session.isCancelled && isToday(session.date)
            && now < session.expectedEnd(schedule: file.course.schedule, classMinutes: workspace.settings.classMinutes, calendar: calendar)
    }

    func importFiles(_ urls: [URL], into session: Session) {
        workspace.importFiles(urls, into: CourseFolder.lectures.rawValue, session: session.id, course: courseId)
    }

    // MARK: Sessions made ahead

    func loadUntouched(_ course: LoadedCourse, now: Date? = nil) {
        let now = now ?? workspace.now
        // 읽지 못한 노트가 어느 회차든 가리킬 수 있으므로 그때는 아무것도 제시하지 않는다.
        guard let notes = try? course.store.notes() else { untouched = []; return }
        untouched = course.file.untouchedFutureSessions(now: now, notedSessions: Set(notes.flatMap(\.meta.sessionIds)))
    }

    var untouchedShown: [Session] { Array(untouched.prefix(4)) }
    var untouchedMore: Int { untouched.count - untouchedShown.count }

    func removeUntouched() {
        pending = workspace.ask(SessionRemove(course: courseId, sessions: untouched.map(\.id)), button: .sessionsRemove)
    }

    // MARK: Classes left unwrapped

    // 시작할 때 목록을 고정해야 저장한 회차가 알림에서 빠져도 시트의 개수가 바뀌지 않는다.
    struct WrapUpRun: Identifiable {
        let id = UUID()
        let sessions: [UUID]
        var index = 0
        var current: UUID { sessions[index] }
    }

    var wrapUpRun: WrapUpRun?

    private func isCurrent(_ file: CourseFile) -> Bool { file.course.semesterId == workspace.currentSemester?.id }

    func leftUnwrapped(_ file: CourseFile, now: Date? = nil) -> [Session] {
        guard isCurrent(file) else { return [] }
        return file.unwrappedPastSessions(at: now ?? workspace.now, settings: workspace.settings, calendar: calendar)
    }

    func leftGaps(_ session: Session, in file: CourseFile, now: Date? = nil) -> [WrapUpItem] {
        guard isCurrent(file), file.isLeftUnwrapped(session, at: now ?? workspace.now, settings: workspace.settings, calendar: calendar)
        else { return [] }
        return file.wrapUpGaps(of: session)
    }

    func gapsLine(_ gaps: [WrapUpItem]) -> String { gaps.map(\.label).joined(separator: ", ") }

    func startWrapUps(_ file: CourseFile) {
        let left = leftUnwrapped(file)
        guard !left.isEmpty else { return }
        wrapUpRun = WrapUpRun(sessions: left.map(\.id))
    }

    func wrappedUpOne() {
        guard var run = wrapUpRun else { return }
        run.index += 1
        wrapUpRun = run.index < run.sessions.count ? run : nil
    }

    func step(of run: WrapUpRun) -> String? {
        run.sessions.count > 1 ? String(localized: .wrapUpStep(run.index + 1, run.sessions.count)) : nil
    }

    // MARK: A session's row

    struct CardTiming {
        let expectedEnd: Date
        let live: Bool
        let progress: Double?
        let offersStart: Bool
    }

    func timing(of session: Session, in file: CourseFile, now: Date) -> CardTiming {
        let end = session.expectedEnd(schedule: file.course.schedule, classMinutes: workspace.settings.classMinutes, calendar: calendar)
        return CardTiming(
            expectedEnd: end, live: isOngoing(session, end: end, now: now), progress: progress(session, end: end, now: now),
            offersStart: offersJoin(session, in: file, now: now))
    }

    func isOngoing(_ session: Session, end: Date?, now: Date) -> Bool {
        !session.isCancelled && end.map { now >= session.date && now < $0 } ?? false
    }

    func progress(_ session: Session, end: Date?, now: Date) -> Double? {
        guard isOngoing(session, end: end, now: now), let end else { return nil }
        return now.timeIntervalSince(session.date) / end.timeIntervalSince(session.date)
    }

    func minutesLeft(until end: Date, now: Date) -> String {
        String(localized: .sessionsMinutesLeft(Int(end.timeIntervalSince(now) / 60) + 1))
    }

    func lateMark(_ session: Session, in file: CourseFile) -> StepToggle<AttendanceState>.Option? {
        let attendance = menu.attendance(of: session)
        return session.isCancelled || attendance == .present ? nil : AttendanceState.steps.first { $0.value == attendance }
    }

    func isToday(_ date: Date) -> Bool { workspace.isStudyToday(date) }

    func title(of session: Session, in file: CourseFile) -> String { file.subject(of: session) ?? String(localized: .sessionsClass) }

    func hasSubject(_ session: Session, in file: CourseFile) -> Bool { file.subject(of: session) != nil }

    enum Review: Equatable {
        case done(UUID), writing(UUID), missing
    }

    func review(of session: Session, in file: CourseFile, now: Date) -> Review? {
        switch (file.review(of: session), session.reviewNoteId) {
        case (.written?, let id?): .done(id)
        case (.writing?, let id?): .writing(id)
        case (.needed?, nil) where session.date <= now: .missing
        default: nil
        }
    }

    func recordingsLabel(_ count: Int) -> String {
        String(localized: count > 1 ? .sessionsRecordingCount(count) : .sessionsRecordingShort)
    }

    func offersWrapUp(_ session: Session) -> Bool { !session.isCancelled && session.date <= workspace.now }

    // MARK: A session's actions

    var menu: SessionMenuModel { SessionMenuModel(workspace: workspace, courseId: courseId) }
}

struct SessionUnits {
    let file: CourseFile
    let session: Session
    let linked: [FolioDomain.Unit]
    let shown: [FolioDomain.Unit]
    let missing: Bool

    init(_ session: Session, in file: CourseFile, now: Date) {
        self.file = file
        self.session = session
        linked = file.units(of: session)
        shown = UnitTree.deepest(linked, in: file.units)
        missing = file.needsUnits(session, at: now)
    }

    var offered: Bool { !file.units.isEmpty && (!linked.isEmpty || !session.skipsReview) }

    var titles: String { shown.map(\.title).joined(separator: " · ") }

    var symbol: String { missing ? "exclamationmark.triangle.fill" : linked.isEmpty ? "plus" : "link" }

    var label: String { shown.isEmpty ? String(localized: missing ? .sessionsUnitsNeeded : .sessionsUnitsLink) : titles }

    var help: String {
        missing
            ? String(localized: .sessionsUnitsMissingHelp)
            : shown.isEmpty
                ? String(localized: .sessionsUnitsHelp)
                : shown.map(\.title).joined(separator: "\n")
    }

    var progress: (material: UUID, pages: ClosedRange<Int>)? { file.splitProgress(of: session) }
}
