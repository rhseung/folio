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

    var current: [LoadedCourse] { workspace.currentCourses }

    var currentRecords: [Course] {
        guard let semester = workspace.currentSemester, semester.term.holdsClasses else { return [] }
        return workspace.records(in: semester)
    }

    struct RecordClass {
        var course: Course
        var meeting: SessionPlanner.Suggestion
    }

    /// A record keeps no sessions, so its classes come straight from its weekly times.
    func recordClasses(on day: LocalDate) -> [RecordClass] {
        guard let semester = workspace.currentSemester else { return [] }
        return currentRecords.flatMap { c in
            SessionPlanner.meetings(schedule: c.schedule, on: day, from: semester.start, to: semester.end, examWeeks: semester.examWeeks,
                                    calendar: workspace.calendar).map { RecordClass(course: c, meeting: $0) }
        }
    }

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

    /// The course whose class is under way: one already made, the timetable's suggestion not made yet, or a record's slot.
    func nowCourse(at now: Date) -> UUID? {
        if let item = workspace.ongoingClass(at: now) { return item.courseId }
        if let item = workspace.suggestedSessions(now: now).first(where: { $0.suggestion.date <= now }) { return item.courseId }
        let day = workspace.settings.studyDay(of: now, calendar: workspace.calendar)
        return recordClasses(on: day).first { $0.meeting.date <= now && now < $0.meeting.end }?.course.id
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
        workspace.course(id)?.title ?? workspace.record(id)?.title ?? ""
    }

    /// `그래프 이론 · 9주차-2`, or the course alone for a record's class, which has no session name.
    func classTitle(_ id: UUID, _ name: String) -> String {
        name.isEmpty ? title(id) : "\(title(id)) · \(name)"
    }

    func sessionName(_ course: UUID, _ session: Session) -> String {
        workspace.course(course)?.file.name(of: session) ?? ""
    }

    func examTitle(_ item: TodaySummary.ExamItem) -> String { "\(title(item.courseId)) · \(item.exam.title)" }

    func dDay(_ item: TodaySummary.ExamItem) -> String { item.dDay == 0 ? "D-day" : "D-\(item.dDay)" }

    func examStart(_ item: TodaySummary.ExamItem) -> String {
        item.exam.start?.formatted(.dateTime.month().day().weekday().hour().minute()) ?? ""
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

    enum DeadlineUrgency { case urgent, soon, later }

    struct DeadlineRow: Identifiable {
        var item: TodaySummary.DeadlineItem
        var urgency: DeadlineUrgency
        var due: String
        var id: UUID { item.assignment.id }
    }

    /// Today and tomorrow are urgent and the rest of the week soon, each said as a span from now; past a week a date reads
    /// quicker than a count of days.
    func deadlineRows(_ items: [TodaySummary.DeadlineItem], studyDay: LocalDate) -> [DeadlineRow] {
        let calendar = workspace.calendar
        return items.compactMap { item in
            guard let due = item.assignment.due else { return nil }
            // Counted in study days, not calendar days: with a 04:00 boundary, 02:00 the night after next is still
            // tomorrow's work, and counting it as two days off would drop it out of the urgent rows.
            let days = studyDay.days(until: workspace.settings.studyDay(of: due, calendar: calendar))
            let time = due.formatted(date: .omitted, time: .shortened)
            return switch days {
            case 0: DeadlineRow(item: item, urgency: .urgent, due: String(localized: .todayDeadlinesTodayAt(time)))
            case 1: DeadlineRow(item: item, urgency: .urgent, due: String(localized: .todayDeadlinesTomorrowAt(time)))
            case ..<7: DeadlineRow(item: item, urgency: .soon, due: String(localized: .todayDeadlinesInDays(days)))
            default: DeadlineRow(item: item, urgency: .later, due: due.formatted(.dateTime.month().day().weekday()))
            }
        }
    }

    /// Past this many deadlines the rest fold behind a button: a term's worth of reports would push the reviews off the page.
    static let deadlineLimit = 6
    var showsAllDeadlines = false

    /// The rows cut to `deadlineLimit` unless unfolded, and how many were left out.
    func shownDeadlines(_ rows: [DeadlineRow]) -> (rows: [DeadlineRow], more: Int) {
        guard !showsAllDeadlines, rows.count > Self.deadlineLimit else { return (rows, 0) }
        return (Array(rows.prefix(Self.deadlineLimit)), rows.count - Self.deadlineLimit)
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
        // A session without a weekly slot has no end; the expected one keeps it a visible block rather than a sliver.
        let made = summary.classesToday.map { item in
            RibbonClass(courseId: item.courseId, start: item.session.date,
                        end: item.session.expectedEnd(schedule: workspace.course(item.courseId)?.file.course.schedule ?? [],
                                                      classMinutes: workspace.settings.classMinutes, calendar: workspace.calendar),
                        name: sessionName(item.courseId, item.session), sessionId: item.session.id)
        }
        let planned = suggested(now: now, on: summary.studyDay).map {
            RibbonClass(courseId: $0.courseId, start: $0.suggestion.date, end: $0.suggestion.end, name: $0.name, suggested: $0)
        }
        let records = recordClasses(on: summary.studyDay).map {
            RibbonClass(courseId: $0.course.id, start: $0.meeting.date, end: $0.meeting.end, name: "")
        }
        return (made + planned + records).sorted { $0.start < $1.start }
    }

    func ribbon(_ classes: [RibbonClass], on day: LocalDate) -> DayRibbon {
        DayRibbon(day: day, classes: classes.map { DateInterval(start: $0.start, end: max($0.start, $0.end)) }, calendar: workspace.calendar)
    }

    /// The next class to start after `now`, made or only on the timetable.
    func nextClass(after now: Date) -> (courseId: UUID, date: Date)? {
        let made = current.flatMap { c in c.file.sessions.filter { !$0.isCancelled && $0.date > now }.map { (courseId: c.id, date: $0.date) } }
        let planned = workspace.suggestedSessions(now: now).filter { $0.suggestion.date > now }.map { (courseId: $0.courseId, date: $0.suggestion.date) }
        // A week and a day reaches the same weekday's class even after today's has passed.
        let today = workspace.settings.studyDay(of: now, calendar: workspace.calendar)
        let records = (0..<8).flatMap { recordClasses(on: today.adding(days: $0)) }.filter { $0.meeting.date > now }
            .map { (courseId: $0.course.id, date: $0.meeting.date) }
        return (made + planned + records).min { $0.date < $1.date }
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
            let slots = inTerm ? (current.map(\.file.course) + currentRecords).flatMap { c in c.schedule.filter { $0.weekday == iso }.map { ($0.startMinute, c.id) } } : []
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
