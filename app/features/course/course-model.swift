import FolioDomain
import Foundation
import Observation

/// The course page: which section is open, the note the notes section shows, and what the course column and the
/// overview draw.
@MainActor @Observable
final class CourseModel {
    let workspace: Workspace
    var pending: PendingAction?
    let courseId: UUID
    /// Every change of section or note is a move the window's history keeps (`place`), unless it came from following
    /// the history itself.
    var section: CourseSection = .overview { didSet { if section != oldValue { settle() } } }
    var openNote: UUID? { didSet { if openNote != oldValue { settle() } } }
    /// The heading or block the open note was linked at, for the preview to scroll to.
    private(set) var noteAnchor: AppLink.Anchor?
    /// The unit the units page has open, reported by it, so a card made in the Claude panel goes there.
    var openUnit: UUID?
    /// Where the page is, as a link: the section, or what is open in it. The view hands each new one to the window.
    private(set) var place: AppLink
    private var following = false
    /// An answer the Claude panel puts at the end of the open note; the editor takes it and clears it.
    var noteInsert: String?
    /// The notes section's last move, made from the list or the open note's name, which the list offers to undo.
    let noteMoves = MoveUndo()

    init(workspace: Workspace, courseId: UUID) {
        self.workspace = workspace
        self.courseId = courseId
        place = .course(courseId)
    }

    var course: LoadedCourse? { workspace.course(courseId) }
    var accent: CourseAccent { workspace.accent(courseId) }

    func show(note id: UUID) {
        openNote = id
        section = .notes
    }

    /// Shows what the window's link names. A material or a unit opens on its own page, which reads `place`; an item
    /// of a list page (a session, an exam) is the page's `focus`.
    func follow(_ entry: Navigator.Entry) {
        guard entry.course == courseId, entry.link != place else { return }
        let link = entry.link
        following = true
        defer { following = false }
        place = link
        noteAnchor = nil
        switch link.kind {
        case .course: section = CourseSection(link.page ?? .overview)
        case .note:
            openNote = link.id
            noteAnchor = link.anchor
            section = .notes
        case .session: section = .sessions
        case .unit: section = .units
        case .material: section = .materials
        case .assignment: section = .assignments
        case .exam: section = .exams
        case .card: section = .quizCards
        case .problemSet: section = .quizProblems
        // Not in a course: `Screen` never hands these to one.
        case .today, .grades, .requirements, .people, .codes, .settings, .semester, .person: break
        }
    }

    /// The item a list page scrolls to and marks (`.linkTarget`): what the window's link named, until the page moves on.
    var focus: UUID? {
        guard let id = place.id else { return nil }
        switch place.kind {
        case .session, .assignment, .exam, .card, .problemSet: return id
        // A note, a file and a unit open on a page of their own; the rest are no item of a page.
        case .note, .material, .unit, .course, .today, .grades, .requirements, .people, .codes, .settings, .semester, .person: return nil
        }
    }

    /// A page opened something of its own (a file, a unit) or closed it, which is a move too. The same file at
    /// another page takes the place over, and the window keeps it on the step it is on (`Navigator.go`).
    func moved(_ link: AppLink?) {
        guard !following else { return }
        guard let link else { return settle() }
        // A file reported before its viewer is on a page keeps the page the link opened it at.
        if link.anchor == nil, link == place.withoutAnchor { return }
        if link != place { place = link }
    }

    /// The section's first screen again, for its crumb: what the section had open is closed.
    func resetPage() {
        settle()
    }

    private func settle() {
        guard !following else { return }
        // A note picked by hand opens at its top, not at the heading the last link pointed to.
        noteAnchor = nil
        if section == .notes, let openNote {
            place = AppLink(.note, openNote)
        } else {
            place = .course(courseId, page: section.page)
        }
    }

    // MARK: Course column

    func recent(_ file: CourseFile) -> [Session] {
        Array(file.sessions.filter { $0.date <= workspace.now && !$0.isCancelled }.sorted { $0.date > $1.date }.prefix(4))
    }

    func recentTitle(_ s: Session, in file: CourseFile) -> String { file.title(of: s, calendar: workspace.calendar) }

    func recentDetail(_ s: Session, in file: CourseFile) -> String { noteState(s, in: file) }

    func noteState(_ session: Session, in file: CourseFile) -> String {
        if session.reviewNoteId != nil { return String(localized: session.reviewNoteUnfinished ? .courseReviewNoteDraft : .courseReviewNote) }
        if session.roughNoteId != nil { return String(localized: .sessionsRoughNote) }
        return String(localized: file.needsReviewNote(session, at: workspace.now) ? .courseReviewNoteMissing : .courseReviewNotNeeded)
    }

    /// What a tab's row shows on its right: a count, a warning, or the projected score once grades are unlocked.
    func trailing(_ tab: CourseTab, file: CourseFile) -> (text: String, warning: Bool)? {
        switch tab {
        case .classes where !file.sessions.isEmpty: return (String(localized: .courseSessionCount(file.sessions.count)), false)
        case .materials:
            let unclassified = unclassified(file).count
            return unclassified > 0 ? (String(localized: .courseUnclassified(unclassified)), true) : nil
        case .assessment:
            guard workspace.gradesUnlocked, let p = score(file).projected else { return nil }
            return (String(localized: .courseProjected(p.oneDecimal)), false)
        default: return nil
        }
    }

    // MARK: Overview

    func score(_ file: CourseFile) -> GradeCalculator.CourseScore { GradeCalculator.score(components: file.components, entries: file.scores) }
    func unclassified(_ file: CourseFile) -> [FolioDomain.Material] { file.materials.filter { $0.status == .unclassified } }
    func reviews(now: Date) -> [Workspace.ReviewEntry] { workspace.reviewQueue(now: now).filter { $0.courseId == courseId } }
    func suggested(_ course: LoadedCourse, now: Date) -> Workspace.SuggestedSession? { workspace.suggestedSession(for: course, now: now) }
    func days(to date: Date) -> Int { workspace.days(to: date) }

    func subtitle(_ file: CourseFile) -> String {
        [workspace.semester(of: file.course)?.title, Self.scheduleLine(file.course.schedule)].compactMap { $0 }.joined(separator: " · ")
    }

    func credits(_ course: Course) -> String { String(localized: .courseCredits(course.credits.formatted())) }

    /// `월·수 13:00–14:15 자연과학동 203`: days sharing a time and room are written once.
    static func scheduleLine(_ schedule: [ClassTime]) -> String? {
        var groups: [(key: String, days: [String])] = []
        for slot in schedule.sorted(by: { ($0.weekday, $0.startMinute) < ($1.weekday, $1.startMinute) }) {
            let key = "\(TimeMenu.range(slot.startMinute, slot.endMinute))" + (slot.room.isEmpty ? "" : " \(slot.room)")
            let day = ClassTime.weekdayNames[slot.weekday - 1]
            if let i = groups.firstIndex(where: { $0.key == key }) { groups[i].days.append(day) } else { groups.append((key, [day])) }
        }
        return groups.isEmpty ? nil : groups.map { $0.days.joined(separator: "·") + " " + $0.key }.joined(separator: ", ")
    }

    /// Monday-based like the app's weeks; the calendar's own week can start on Sunday.
    func thisWeek(now: Date) -> DateInterval {
        let start = workspace.calendar.startOfWeek(containing: now)
        return DateInterval(start: start, end: workspace.calendar.date(byAdding: .day, value: 7, to: start) ?? start)
    }

    func weekSessions(_ file: CourseFile, now: Date) -> [Session] {
        let week = thisWeek(now: now)
        return file.sessions.filter { week.contains($0.date) }.sorted { $0.date < $1.date }
    }

    /// The class the timetable says comes next this week, before it is made.
    func weekSuggestion(_ suggested: Workspace.SuggestedSession?, now: Date) -> Workspace.SuggestedSession? {
        suggested.flatMap { thisWeek(now: now).contains($0.suggestion.date) ? $0 : nil }
    }

    func weekStatus(_ s: Session, in file: CourseFile, now: Date) -> String {
        if s.isCancelled { return String(localized: .sessionsCancelled) }
        if s.date > now { return String(localized: .coursePlanned) }
        if s.reviewNoteId != nil { return String(localized: s.reviewNoteUnfinished ? .courseReviewNoteDraft : .courseReviewNote) }
        return String(localized: file.needsReviewNote(s, at: now) ? .courseReviewNoteMissing : .courseReviewNotNeeded)
    }

    func day(of date: Date) -> Int { workspace.calendar.component(.day, from: date) }

    func openAssignments(_ file: CourseFile) -> [Assignment] {
        file.assignments.filter(\.status.isOpen).sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
    }

    func assignmentsNote(_ file: CourseFile) -> String? {
        file.assignments.isEmpty ? nil : String(localized: .courseAssignmentsNote(file.assignments.count, file.assignments.count - openAssignments(file).count))
    }

    /// A glance, not the list: the units due first, then the ones taught most recently.
    func glanceUnits(_ file: CourseFile, reviews: [Workspace.ReviewEntry]) -> [FolioDomain.Unit] {
        let due = reviews.compactMap { r in file.units.first { $0.id == r.item.unitId } }
        let covered = UnitTree.outline(file.units).map(\.unit).filter { u in !u.sessionIds.isEmpty && !due.contains { $0.id == u.id } }
        return Array((due + covered.suffix(8).reversed()).prefix(8))
    }

    func skipReview(_ unit: FolioDomain.Unit) { pending = workspace.skipReviews([(courseId, unit.id)]) }

    func stats(_ file: CourseFile, reviews: [Workspace.ReviewEntry], suggested: Workspace.SuggestedSession?, now: Date) -> [StatStrip.Item] {
        // A class the timetable promises counts before it is made; without it a course that makes sessions as it goes
        // never showed a next class.
        let made: (date: Date, subject: String?)? = file.sessions.filter { $0.date > now && !$0.isCancelled }.min { $0.date < $1.date }
            .map { (date: $0.date, subject: file.subject(of: $0)) }
        let planned: (date: Date, subject: String?)? = suggested.flatMap { $0.suggestion.date > now ? (date: $0.suggestion.date, subject: nil) : nil }
        let nextClass = [made, planned].compactMap { $0 }.min { $0.date < $1.date }
        let nextExam = file.exams.compactMap { e in e.start.map { (e, $0) } }.filter { $0.1 > now }.min { $0.1 < $1.1 }
        let nextDue = file.assignments.compactMap { a in a.due.map { (a, $0) } }
            .filter { $0.1 > now && $0.0.status.isOpen }.min { $0.1 < $1.1 }
        let maxOverdue = reviews.map(\.item.overdueDays).max() ?? 0

        var items: [StatStrip.Item] = []
        if let next = nextClass {
            // The weekday rides in the detail: with it the date was cut off in a narrow window.
            items.append(.init(title: String(localized: .courseNextClass), value: next.date.formatted(.dateTime.month().day()),
                               detail: "\(next.date.formatted(.dateTime.weekday())) \(next.date.formatted(date: .omitted, time: .shortened))" + (next.subject.map { " · \($0)" } ?? "")))
        } else {
            items.append(.init(title: String(localized: .courseNextClass), value: "-"))
        }
        if let (exam, start) = nextExam {
            let d = days(to: start)
            items.append(.init(title: String(localized: .courseNextExam), value: "\(exam.title) \(d == 0 ? "D-day" : "D-\(d)")",
                               detail: start.formatted(.dateTime.month().day().weekday()), tone: d <= 7 ? .danger : .plain))
        } else {
            items.append(.init(title: String(localized: .courseNextExam), value: "-"))
        }
        items.append(.init(title: String(localized: .courseReviewToday), value: String(localized: .courseUnitsValue(reviews.count)),
                           detail: maxOverdue > 0 ? String(localized: .courseMaxOverdue(maxOverdue)) : nil, tone: maxOverdue > 0 ? .warning : .plain))
        items.append(.init(title: String(localized: .courseNearestDue), value: nextDue?.0.title ?? "-", detail: nextDue?.1.formatted(.dateTime.month().day().weekday().hour().minute())))
        // Each figure opens the page it sums up, in the order appended above.
        for (i, target) in [CourseSection.sessions, .exams, .units, .assignments].enumerated() { items[i].action = { [weak self] in self?.section = target } }
        return items
    }
}
