import FolioActions
import FolioCore
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
        return String(localized: .sessionsNextExam(exam.title, DateTimeText.dday(days: days)))
    }

    private func plan(now: Date) -> [Workspace.SuggestedSession] {
        workspace.course(courseId).map { workspace.plannedSessions(for: $0, now: now) } ?? []
    }

    static func minute(of date: Date, in calendar: Calendar) -> Int {
        calendar.minuteOfDay(date)
    }

    static func weekdayTime(_ date: Date, in calendar: Calendar) -> String {
        date.formatted(.dateTime.weekday()) + " " + TimePicker.label(minute(of: date, in: calendar))
    }

    func examDays(_ exam: Exam, now: Date) -> Int? {
        exam.start.flatMap { $0 > now ? max(workspace.days(to: $0), 0) : nil }
    }

    // MARK: The week table

    // 자기 폭으로 꼴을 고른다. 재기 전(0)에는 가장 좁은 꼴로 그려, 처음 그릴 때 넓은 표가 좁은 칸을 넘치지 않게 한다.
    var width: CGFloat = 0
    var popover: UUID?
    var anchor: PageAnchor?
    @ObservationIgnored private var placed = false

    enum Form { case list, compact, wide }

    var form: Form {
        width < Theme.Size.sessionTableList ? .list : width < Theme.Size.sessionTableWide ? .compact : .wide
    }

    func table(_ file: CourseFile, now: Date? = nil) -> SessionTable {
        let now = now ?? workspace.now
        return SessionTable(
            file, planned: plan(now: now).map(\.draft), semester: workspace.semester(of: file.course), now: now,
            settings: workspace.settings, asksWrapUp: isCurrent(file), calendar: calendar)
    }

    // 처음 열면 이번 주로 스크롤한다. 링크가 회차를 가리키면 그 주로 스크롤하고 그 회차를 연다.
    func follow(_ focus: UUID?, in table: SessionTable) {
        if let focus, let week = table.week(containing: focus) {
            anchor = PageAnchor(week)
            popover = focus
        } else if !placed {
            anchor = PageAnchor(table.thisWeek)
        }
        placed = true
    }

    func showThisWeek(_ table: SessionTable) { anchor = PageAnchor(table.thisWeek) }

    func open(_ session: UUID) { popover = session }

    func columnTitle(_ column: SessionTable.Column) -> String { ClassTime.weekdayNames[column.weekday - 1] }

    func columnDetail(_ column: SessionTable.Column) -> String {
        let times = column.slots.map { TimePicker.range($0.startMinute, $0.endMinute) }
        let rooms = Array(Set(column.slots.map(\.room).filter { !$0.isEmpty })).sorted()
        return (times + rooms).joined(separator: " · ")
    }

    func weekLabel(_ week: SessionTable.Week) -> String { String(localized: .sessionsWeek(week.number)) }

    func weekRange(_ week: SessionTable.Week) -> String { shortDay(week.start) + "–" + shortDay(week.end) }

    func shortDay(_ day: LocalDate) -> String { "\(day.month)/\(day.day)" }

    func weekday(_ day: LocalDate) -> String {
        ClassTime.weekdayNames[(day.date(in: calendar).map(calendar.isoWeekday(of:)) ?? 1) - 1]
    }

    func dayNumber(_ day: LocalDate) -> String { String(day.day) }

    // 칸의 날짜는 달의 첫날에만 달을 붙인다. 주가 두 달에 걸칠 때 어디서 달이 바뀌는지 보인다.
    func chipDay(_ day: LocalDate) -> String { day.day == 1 ? shortDay(day) : String(day.day) }

    func month(_ month: Int) -> String { String(localized: .sessionsMonth(month)) }

    func spokenDay(_ day: LocalDate) -> String {
        day.date(in: calendar)?.formatted(.dateTime.month().day().weekday(.wide)) ?? shortDay(day)
    }

    func title(_ entry: SessionTableEntry) -> String {
        if let subject = entry.subject { return subject }
        return String(localized: entry.look == .next ? .sessionsTableNext : .sessionsClass)
    }

    func isUntitled(_ entry: SessionTableEntry) -> Bool { entry.subject == nil && entry.look != .next }

    // 블록의 줄 하나다. "그 밖" 칸은 앞에 요일과 날짜를 붙인다. 회차의 시각은 시간표와 다를 때만 쓴다.
    func line(_ entry: SessionTableEntry, other: Bool) -> String? {
        var parts: [String] = other ? [weekday(entry.day) + " " + shortDay(entry.day)] : []
        let minute = calendar.minuteOfDay(entry.date)
        switch entry.item {
        case .session, .planned:
            if entry.offSchedule { parts.append(TimePicker.label(minute)) }
            if let pages = entry.pages { parts.append(String(localized: .sessionsTablePages(pages.lowerBound, pages.upperBound))) }
        case .exam(let exam):
            parts.append(exam.end.map { TimePicker.range(minute, calendar.minuteOfDay($0)) } ?? TimePicker.label(minute))
            if !exam.location.isEmpty { parts.append(exam.location) }
        case .deadline:
            break
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    func deadline(_ entry: SessionTableEntry, other: Bool) -> String {
        let text = String(localized: .sessionsTableDue(entry.subject ?? "", TimePicker.label(calendar.minuteOfDay(entry.date))))
        return other ? weekday(entry.day) + " " + shortDay(entry.day) + " " + text : text
    }

    struct BlockTag: Hashable {
        let text: String?
        let symbol: String?
        let tone: Tone
        let spoken: String
        // 사용자가 적은 범위는 길이를 알 수 없어서, 칸보다 길면 한 줄에서 자른다.
        var truncates = false
    }

    func tags(_ entry: SessionTableEntry) -> [BlockTag] {
        entry.tags.map { tag in
            switch tag {
            case .attendance(let state):
                BlockTag(
                    text: state.label, symbol: nil, tone: state == .late ? .warning : state == .absent ? .danger : .plain,
                    spoken: state.label)
            case .makeup: word(String(localized: .sessionsMakeup), .accent)
            case .cancelled: word(String(localized: .sessionsCancelled), .plain)
            case .unwrapped: word(String(localized: .sessionsTableUnwrapped), .warning)
            case .noReviewNote: word(String(localized: .sessionsTableNoReviewNote), .danger)
            case .scope(let scope): BlockTag(text: scope, symbol: nil, tone: .plain, spoken: scope, truncates: true)
            case .linkedUnits(let units):
                BlockTag(
                    text: nil, symbol: "link", tone: .plain,
                    spoken: String(localized: .sessionsTableLinkedUnits(units.joined(separator: ", "))))
            case .recording(let seconds):
                BlockTag(
                    text: nil, symbol: "waveform", tone: .plain,
                    spoken: String(localized: .sessionsTableRecording(RecordingTime.label(seconds))))
            case .reviewNote:
                BlockTag(text: nil, symbol: "doc.text", tone: .plain, spoken: String(localized: .sessionsTableReviewNote))
            }
        }
    }

    private func word(_ text: String, _ tone: Tone) -> BlockTag { BlockTag(text: text, symbol: nil, tone: tone, spoken: text) }

    // 아이콘만 보이는 태그도 낭독기에는 글로 남긴다.
    func spoken(_ entry: SessionTableEntry) -> String {
        let name: String = if case .deadline = entry.item { deadline(entry, other: false) } else { title(entry) }
        let planned = entry.look == .upcoming || entry.look == .next ? [String(localized: .sessionsTablePlanned)] : []
        return ([spokenDay(entry.day), name] + [line(entry, other: false)].compactMap { $0 } + tags(entry).map(\.spoken) + planned)
            .joined(separator: ", ")
    }

    func spokenEmpty(_ day: LocalDate) -> String { String(localized: .sessionsTableAddOn(spokenDay(day))) }

    func popoverTitle(_ session: Session, in file: CourseFile) -> String {
        let day = LocalDate(session.date, in: calendar)
        return shortDay(day) + "(" + weekday(day) + "): " + (file.subject(of: session) ?? String(localized: .sessionsClass))
    }

    // 주차는 표가 정한 번호를 그대로 쓴다. 따로 세면 학기 시작이 없을 때 표와 팝오버의 번호가 달라진다.
    func popoverDetail(_ session: Session, in file: CourseFile, table: SessionTable) -> String {
        let monday = table.week(containing: session.id)
        let week = table.weeks.first { $0.start == monday }.map { String(localized: .sessionsWeek($0.number)) }
        let start = calendar.minuteOfDay(session.date)
        let time =
            session.end(schedule: file.course.schedule, calendar: calendar).map { TimePicker.range(start, calendar.minuteOfDay($0)) }
            ?? TimePicker.label(start)
        let room = session.slot(in: file.course.schedule, calendar: calendar)?.room ?? ""
        return ([week, session.date.formatted(.dateTime.weekday(.wide)) + " " + time].compactMap { $0 } + (room.isEmpty ? [] : [room]))
            .joined(separator: " · ")
    }

    func asksWrapUp(_ session: Session, in table: SessionTable) -> Bool {
        table.weeks.lazy.flatMap(\.cells).flatMap(\.entries).first { $0.session?.id == session.id }?.tags.contains(.unwrapped) ?? false
    }

    func planned(_ entry: SessionTableEntry) -> Workspace.SuggestedSession? {
        guard case .planned(let draft) = entry.item else { return nil }
        return plan(now: workspace.now).first { $0.draft.date == draft.date }
    }

    func link(_ entry: SessionTableEntry) -> AppLink? {
        switch entry.item {
        case .exam(let exam): AppLink(.exam, exam.id)
        case .deadline(let assignment): AppLink(.assignment, assignment.id)
        case .session, .planned: nil
        }
    }

    // 그날로 회차 추가 시트를 연다. 그 요일에 수업이 있으면 첫 수업 시각으로 연다.
    func addRequest(on day: LocalDate, in table: SessionTable) -> SessionSheetRequest? {
        guard let midnight = day.date(in: calendar) else { return nil }
        let weekday = calendar.isoWeekday(of: midnight)
        let minute = table.columns.first { $0.weekday == weekday }?.slots.first?.startMinute ?? 0
        return SessionSheetRequest(course: courseId, start: calendar.date(byAdding: .minute, value: minute, to: midnight))
    }

    func importFiles(_ urls: [URL], into session: Session) {
        workspace.importFiles(urls, into: CourseFolder.lectures.rawValue, session: session.id, course: courseId)
    }

    // MARK: Sessions made ahead

    func loadUntouched(_ course: LoadedCourse, now: Date? = nil) {
        let now = now ?? workspace.now
        // 이미 읽은 문서로 노트를 고른다. `notes()`는 메인 스레드에서 course.json을 한 번 더 읽는다.
        let notes = course.store.notes(in: course.file)
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

    // MARK: A session's actions

    var menu: SessionMenuModel { SessionMenuModel(workspace: workspace, courseId: courseId) }
}
