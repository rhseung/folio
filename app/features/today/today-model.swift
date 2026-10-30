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
            return NowClass(courseId: item.courseId, name: course.file.name(of: item.session), room: room, start: item.session.date, end: item.end)
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

    struct DeadlineDay {
        var id: Date
        var day: String
        var label: String
        var isToday: Bool
        var items: [TodaySummary.DeadlineItem]
    }

    /// The month shows only where it turns, so the column reads as a calendar without repeating it on every day.
    func deadlineDays(_ items: [TodaySummary.DeadlineItem], studyDay: LocalDate) -> [DeadlineDay] {
        let calendar = workspace.calendar
        var days: [DeadlineDay] = []
        var month = studyDay.month
        for item in items {
            guard let due = item.assignment.due else { continue }
            // Before the day boundary a 1am due is still today's though its calendar date is the next one.
            let start = item.isToday ? (studyDay.date(in: calendar) ?? calendar.startOfDay(for: due)) : calendar.startOfDay(for: due)
            if days.last?.id == start { days[days.count - 1].items.append(item); continue }
            let m = item.isToday ? studyDay.month : calendar.component(.month, from: due)
            let label = item.isToday ? String(localized: .todayDeadlinesToday)
                : due.formatted(m == month ? .dateTime.weekday() : .dateTime.month().weekday())
            days.append(DeadlineDay(id: start, day: String(item.isToday ? studyDay.day : calendar.component(.day, from: due)),
                                    label: label, isToday: item.isToday, items: [item]))
            month = m
        }
        return days
    }

    func reviewSubtitle(_ entry: Workspace.ReviewEntry) -> String {
        entry.item.writeNoteFirst ? String(localized: .todayReviewsWriteNoteFirst(title(entry.courseId))) : title(entry.courseId)
    }

    func noteTitle(_ item: TodaySummary.SessionItem) -> String { "\(title(item.courseId)) · \(sessionName(item.courseId, item.session))" }

    func noteSubtitle(_ item: TodaySummary.SessionItem) -> String {
        let day = item.session.date.formatted(.dateTime.month().day().weekday())
        return String(localized: item.session.reviewNoteUnfinished ? .todayNoteContinue(day) : .todayNoteWrite(day))
    }
}
