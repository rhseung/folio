import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Observation

@MainActor @Observable
final class TodayModel {
    let workspace: Workspace

    init(workspace: Workspace) { self.workspace = workspace }

    struct Reviews {
        /// Due today, in priority order.
        var queue: [Workspace.ReviewEntry]
        /// Over the daily cap, moved to tomorrow.
        var deferred: [Workspace.ReviewEntry]
        var doneToday: Int
        var streak: Int
        var all: [Workspace.ReviewEntry] { queue + deferred }
    }

    /// Where the 지금 수업 card's class comes from: one already made, or the timetable's suggestion not made yet.
    struct NowClass {
        var courseId: UUID
        var name: String
        var room: String
        var start: Date
        var end: Date
        var sessionId: UUID?
        var suggested: Workspace.SuggestedSession?
    }

    var current: [LoadedCourse] { workspace.currentCourses }

    var nextDayStart: Date {
        let calendar = workspace.calendar
        let start = workspace.today.date(in: calendar).flatMap { calendar.date(byAdding: .minute, value: workspace.settings.dayBoundaryMinutes, to: $0) }
        return start.flatMap { calendar.date(byAdding: .day, value: 1, to: $0) } ?? .distantFuture
    }

    func summary(now: Date) -> TodaySummary {
        TodaySummary.build(courses: current.map(\.file), now: now, settings: workspace.settings, calendar: workspace.calendar)
    }

    /// The study day, not the calendar date: until the day boundary the classes and reviews below are still
    /// the previous day's, and a title saying otherwise contradicts them.
    func heading(_ summary: TodaySummary, now: Date) -> String {
        (summary.studyDay.date(in: workspace.calendar) ?? now).formatted(.dateTime.month().day().weekday(.wide))
    }

    func reviews(now: Date) -> Reviews {
        let queue = workspace.reviewQueue(now: now)
        let progress = reviewProgress(now: now)
        return Reviews(queue: queue.filter { $0.item.deferred == nil }, deferred: queue.filter { $0.item.deferred != nil },
                       doneToday: progress.doneToday, streak: progress.streak)
    }

    /// Units reviewed today (skips aside, which aren't study) and the days-in-a-row streak, across every course.
    func reviewProgress(now: Date) -> (doneToday: Int, streak: Int) {
        let today = workspace.settings.studyDay(of: now, calendar: workspace.calendar)
        var done = Set<UUID>()
        var days = Set<LocalDate>()
        for courseId in workspace.reviewEvents.keys {
            for r in workspace.reviews(of: courseId) where r.event.result != .skip {
                let day = workspace.settings.studyDay(of: r.at, calendar: workspace.calendar)
                days.insert(day)
                if day == today { done.insert(r.event.unitId) }
            }
        }
        return (done.count, ReviewStreak.days(days, today: today))
    }

    func skip(_ entries: [Workspace.ReviewEntry]) {
        workspace.skipReviews(entries.map { ($0.courseId, $0.item.unitId) })
    }

    /// Timetable suggestions for the study day on screen: past midnight but before the boundary, tomorrow's aren't today's.
    func suggested(now: Date, on day: LocalDate) -> [Workspace.SuggestedSession] {
        workspace.suggestedSessions(now: now).filter { workspace.settings.studyDay(of: $0.suggestion.date, calendar: workspace.calendar) == day }
    }

    /// The study day's courses in class order, each once: the page's wash takes their colors left to right.
    func washCourses(_ summary: TodaySummary, now: Date) -> [UUID] {
        let classes = summary.classesToday.map { ($0.session.date, $0.courseId) }
            + suggested(now: now, on: summary.studyDay).map { ($0.suggestion.date, $0.courseId) }
        var seen = Set<UUID>()
        return classes.sorted { $0.0 < $1.0 }.map(\.1).filter { seen.insert($0).inserted }
    }

    func end(of item: TodaySummary.SessionItem) -> Date? {
        item.session.end(schedule: workspace.course(item.courseId)?.file.course.schedule ?? [], calendar: workspace.calendar)
    }

    func nowClass(at now: Date) -> NowClass? {
        if let item = workspace.ongoingClass(at: now), let course = workspace.course(item.courseId) {
            let room = course.file.course.schedule.first { $0.weekday == workspace.calendar.isoWeekday(of: item.session.date) }?.room ?? ""
            return NowClass(courseId: item.courseId, name: course.file.name(of: item.session), room: room, start: item.session.date, end: item.end, sessionId: item.session.id)
        }
        // Under way but not made yet: the card offers what starting the class needs.
        guard let item = workspace.suggestedSessions(now: now).first(where: { $0.suggestion.date <= now }) else { return nil }
        return NowClass(courseId: item.courseId, name: item.name, room: item.suggestion.room, start: item.suggestion.date,
                        end: item.suggestion.end, suggested: item)
    }

    /// The newest `limit` sessions missing a review note, newest first, and how many older ones are left out.
    func noteRows<Item>(_ items: [Item], limit: Int) -> (shown: [Item], more: Int) {
        let shown = Array(items.suffix(limit).reversed())
        return (shown, items.count - shown.count)
    }

    struct NoteGroup: Identifiable {
        let label: String
        var items: [TodaySummary.SessionItem]
        var id: String { label }
    }

    static let noteLimit = 6
    var showsAllNotes = false

    /// The newest notes first, under the day their class was (`오늘`, `어제`, a weekday), cut to `noteLimit` unless unfolded.
    func noteGroups(_ items: [TodaySummary.SessionItem], today: LocalDate) -> (groups: [NoteGroup], more: Int) {
        let (shown, more) = noteRows(items, limit: showsAllNotes ? items.count : Self.noteLimit)
        var groups: [NoteGroup] = []
        for item in shown {
            let label = sessionWhen(item, today: today)
            if groups.last?.label == label { groups[groups.count - 1].items.append(item) } else { groups.append(NoteGroup(label: label, items: [item])) }
        }
        return (groups, more)
    }

    func reviewNote(of item: TodaySummary.SessionItem) -> UUID? {
        workspace.note(.review, of: item.session.id, in: item.courseId)
    }

    func finishReviewNote(_ item: TodaySummary.SessionItem) {
        workspace.setReviewNoteUnfinished(false, of: item.session.id, in: item.courseId)
    }

    func skipReviewNote(_ item: TodaySummary.SessionItem) {
        workspace.setSkipsReview(true, of: item.session.id, in: item.courseId)
    }

    var attendanceWarnings: [(course: LoadedCourse, absences: Int, cap: AttendanceCap)] {
        current.compactMap { course in course.file.capOneAway(at: workspace.now).map { (course, $0.absences, $0.cap) } }
    }

    func capLabel(_ cap: AttendanceCap) -> String {
        String(localized: .todayAttendanceCap(workspace.catalog.grade(cap.maxGrade)?.symbol ?? String(localized: .todayAttendanceCapFallback)))
    }

    // MARK: Labels

    func title(_ id: UUID) -> String {
        workspace.course(id)?.title ?? ""
    }

    func sessionName(_ course: UUID, _ session: Session) -> String {
        workspace.course(course)?.file.name(of: session) ?? ""
    }

    func examTitle(_ item: TodaySummary.ExamItem) -> String { "\(title(item.courseId)) · \(item.exam.title)" }

    func dDay(_ item: TodaySummary.ExamItem) -> String { item.dDay == 0 ? "D-day" : "D-\(item.dDay)" }

    func examStart(_ item: TodaySummary.ExamItem) -> String {
        item.exam.start?.formatted(.dateTime.month().day().weekday().hour().minute()) ?? ""
    }

    func due(_ item: TodaySummary.DeadlineItem) -> String {
        guard let due = item.assignment.due else { return "" }
        return item.isToday ? due.formatted(date: .omitted, time: .shortened) : due.formatted(.dateTime.month().day().weekday())
    }

    struct EditingAssignment: Identifiable {
        var course: LoadedCourse
        var assignment: Assignment
        var id: UUID { assignment.id }
    }

    var editing: EditingAssignment?

    func edit(_ item: TodaySummary.DeadlineItem) {
        guard let course = workspace.course(item.courseId) else { return }
        editing = EditingAssignment(course: course, assignment: item.assignment)
    }

    enum DeadlineWhen: Int, CaseIterable {
        case today, thisWeek, nextWeek, later
    }

    struct DeadlineGroup: Identifiable {
        var when: DeadlineWhen
        var items: [TodaySummary.DeadlineItem]
        var id: DeadlineWhen { when }
    }

    /// Weeks run Monday to Sunday, the way the timetable repeats, so "다음 주" is the next run of the same classes.
    func deadlineGroups(_ items: [TodaySummary.DeadlineItem], studyDay: LocalDate) -> [DeadlineGroup] {
        let calendar = workspace.calendar
        let weekday = studyDay.date(in: calendar).map { calendar.isoWeekday(of: $0) } ?? 1
        let nextMonday = studyDay.adding(days: 8 - weekday)
        func when(_ item: TodaySummary.DeadlineItem) -> DeadlineWhen {
            if item.isToday { return .today }
            guard let due = item.assignment.due else { return .later }
            let day = LocalDate(due, in: calendar)
            return day < nextMonday ? .thisWeek : day < nextMonday.adding(days: 7) ? .nextWeek : .later
        }
        let grouped = Dictionary(grouping: items, by: when)
        return DeadlineWhen.allCases.compactMap { w in grouped[w].map { DeadlineGroup(when: w, items: $0) } }
    }

    /// Past this many deadlines the rest fold behind a button: a term's worth of reports would push the reviews off the page.
    static let deadlineLimit = 6
    var showsAllDeadlines = false

    /// The groups cut to `deadlineLimit` items unless unfolded, and how many were left out.
    func shownDeadlines(_ groups: [DeadlineGroup]) -> (groups: [DeadlineGroup], more: Int) {
        let total = groups.map(\.items.count).reduce(0, +)
        guard !showsAllDeadlines, total > Self.deadlineLimit else { return (groups, 0) }
        var left = Self.deadlineLimit
        let cut = groups.compactMap { g -> DeadlineGroup? in
            guard left > 0 else { return nil }
            defer { left -= min(left, g.items.count) }
            return DeadlineGroup(when: g.when, items: Array(g.items.prefix(left)))
        }
        return (cut, total - Self.deadlineLimit)
    }

    func groupLabel(_ when: DeadlineWhen) -> String {
        switch when {
        case .today: String(localized: .todayDeadlinesToday)
        case .thisWeek: String(localized: .todayDeadlinesThisWeek)
        case .nextWeek: String(localized: .todayDeadlinesNextWeek)
        case .later: String(localized: .todayDeadlinesLater)
        }
    }

    // MARK: Day ribbon

    /// A class on the ribbon: a session already made, or the timetable's lecture not made yet.
    struct RibbonClass: Identifiable {
        var courseId: UUID
        var start: Date
        var end: Date
        var name: String
        var sessionId: UUID?
        var suggested: Workspace.SuggestedSession?
        var id: String { "\(courseId)-\(start.timeIntervalSinceReferenceDate)" }
    }

    func ribbonClasses(_ summary: TodaySummary, now: Date) -> [RibbonClass] {
        // A session without a weekly slot has no end; an hour keeps it a visible block rather than a sliver.
        let made = summary.classesToday.map { item in
            RibbonClass(courseId: item.courseId, start: item.session.date, end: end(of: item) ?? item.session.date.addingTimeInterval(3600),
                        name: sessionName(item.courseId, item.session), sessionId: item.session.id)
        }
        let planned = suggested(now: now, on: summary.studyDay).map {
            RibbonClass(courseId: $0.courseId, start: $0.suggestion.date, end: $0.suggestion.end, name: $0.name, suggested: $0)
        }
        return (made + planned).sorted { $0.start < $1.start }
    }

    func ribbon(_ classes: [RibbonClass], on day: LocalDate) -> DayRibbon {
        DayRibbon(day: day, classes: classes.map { DateInterval(start: $0.start, end: max($0.start, $0.end)) }, calendar: workspace.calendar)
    }

    /// The next class to start after `now`, made or only on the timetable.
    func nextClass(after now: Date) -> (courseId: UUID, date: Date)? {
        let made = current.flatMap { c in c.file.sessions.filter { !$0.isCancelled && $0.date > now }.map { (courseId: c.id, date: $0.date) } }
        let planned = workspace.suggestedSessions(now: now).filter { $0.suggestion.date > now }.map { (courseId: $0.courseId, date: $0.suggestion.date) }
        return (made + planned).min { $0.date < $1.date }
    }

    /// The 지금 수업 card's side panel: the class after this one, or how tomorrow starts once today's are done.
    func nextPanel(now: Date, studyDay: LocalDate) -> (title: String, detail: String) {
        let next = nextClass(after: now)
        let day = next.map { workspace.settings.studyDay(of: $0.date, calendar: workspace.calendar) }
        if let next, day == studyDay { return (title(next.courseId), time(next.date)) }
        let tomorrow = next.flatMap { day == studyDay.adding(days: 1) ? $0 : nil }
        return (String(localized: .todayNextTodayDone),
                tomorrow.map { String(localized: .todayNextTomorrow(time($0.date))) } ?? String(localized: .todayNextTomorrowNone))
    }

    /// `월요일 오전 9:00`, the line an empty day's ribbon gives for the next class; the date too once it's over a week out.
    func nextClassLine(after now: Date) -> (when: String, courseId: UUID)? {
        guard let next = nextClass(after: now) else { return nil }
        let soon = next.date.timeIntervalSince(now) < 6 * 86_400
        return (next.date.formatted(soon ? .dateTime.weekday(.wide).hour().minute() : .dateTime.month().day().weekday().hour().minute()), next.courseId)
    }

    func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }

    // MARK: Header

    struct WeekDay: Identifiable {
        var day: LocalDate
        var weekday: String
        var isToday: Bool
        /// Courses with a class time that weekday, in class order.
        var courses: [UUID]
        var id: LocalDate { day }
    }

    /// The week around the study day, each day dotted with the courses the timetable puts on it.
    func week(around studyDay: LocalDate) -> [WeekDay] {
        let calendar = workspace.calendar
        let weekday = studyDay.date(in: calendar).map { calendar.isoWeekday(of: $0) } ?? 1
        let semester = workspace.currentSemester
        return (1...7).map { iso in
            let day = studyDay.adding(days: iso - weekday)
            let inTerm = (semester?.start.map { $0 <= day } ?? true) && (semester?.end.map { day <= $0 } ?? true)
            let slots = inTerm ? current.flatMap { c in c.file.course.schedule.filter { $0.weekday == iso }.map { ($0.startMinute, c.id) } } : []
            var seen = Set<UUID>()
            let courses = slots.sorted { $0.0 < $1.0 }.map(\.1).filter { seen.insert($0).inserted }
            return WeekDay(day: day, weekday: ClassTime.weekdayNames[iso - 1], isToday: day == studyDay, courses: courses)
        }
    }

    /// The line under the date, as Markdown-styled pieces whose bold runs are the counts; `urgent` colors them.
    func summaryLine(classes: [RibbonClass], summary: TodaySummary, reviews: Reviews, now: Date) -> [(text: AttributedString, urgent: Bool)] {
        var pieces: [(AttributedString, Bool)] = []
        let ended = classes.filter { $0.end <= now }.count
        pieces.append((classes.isEmpty ? AttributedString(localized: .todayLineNoClasses)
                       : ended == classes.count ? AttributedString(localized: .todayLineClassesDone(classes.count))
                       : ended > 0 ? AttributedString(localized: .todayLineClassesEnded(classes.count, ended))
                       : AttributedString(localized: .todayLineClasses(classes.count)), false))
        let due = summary.deadlines.filter(\.isToday).count
        if due > 0 { pieces.append((AttributedString(localized: .todayLineDue(due)), true)) }
        let left = reviews.queue.count + summary.missingReviewNotes.count
        if left > 0 {
            pieces.append((AttributedString(localized: .todayLineReviews(left)), false))
        } else if reviews.doneToday > 0 {
            pieces.append((AttributedString(localized: .todayLineReviewsDone), false))
        }
        return pieces
    }

    // MARK: Reviews

    struct UnitGroup: Identifiable {
        var courseId: UUID
        /// Each entry with its place in the whole queue, which `ReviewOpener` walks on from.
        var entries: [(index: Int, entry: Workspace.ReviewEntry)]
        var id: UUID { courseId }
        var overdue: Int { entries.map(\.entry.item.overdueDays).max() ?? 0 }
        var writeNoteFirst: Bool { entries.contains { $0.entry.item.writeNoteFirst } }
    }

    /// The queue by course, courses in the order their first unit comes, so the most urgent course leads.
    func unitGroups(_ queue: [Workspace.ReviewEntry]) -> [UnitGroup] {
        var groups: [UnitGroup] = []
        for (i, entry) in queue.enumerated() {
            if let g = groups.firstIndex(where: { $0.courseId == entry.courseId }) {
                groups[g].entries.append((i, entry))
            } else {
                groups.append(UnitGroup(courseId: entry.courseId, entries: [(i, entry)]))
            }
        }
        return groups
    }

    static let unitLimit = 6
    var expandedUnitGroups: Set<UUID> = []

    func shownUnits(_ group: UnitGroup) -> (entries: [(index: Int, entry: Workspace.ReviewEntry)], more: Int) {
        guard !expandedUnitGroups.contains(group.courseId), group.entries.count > Self.unitLimit else { return (group.entries, 0) }
        return (Array(group.entries.prefix(Self.unitLimit)), group.entries.count - Self.unitLimit)
    }

    /// `오늘`, `어제`, or the weekday within the week, then the date: the name of a review-note group.
    func sessionWhen(_ item: TodaySummary.SessionItem, today: LocalDate) -> String {
        let day = workspace.settings.studyDay(of: item.session.date, calendar: workspace.calendar)
        let gap = day.days(until: today)
        return gap == 0 ? String(localized: .todayWhenToday) : gap == 1 ? String(localized: .todayWhenYesterday)
            : item.session.date.formatted(gap < 7 ? .dateTime.weekday(.wide) : .dateTime.month().day())
    }
}
