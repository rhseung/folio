import FolioDomain
import Foundation
import Observation

/// The course page: which section is open, the note the notes section shows, and what the course column and the
/// overview draw.
@MainActor @Observable
final class CourseModel {
    let workspace: Workspace
    let courseId: UUID
    var section: CourseSection = .overview
    var openNote: UUID?
    /// An answer the Claude panel puts at the end of the open note; the editor takes it and clears it.
    var noteInsert: String?

    init(workspace: Workspace, courseId: UUID) {
        self.workspace = workspace
        self.courseId = courseId
    }

    var course: LoadedCourse? { workspace.course(courseId) }
    var accent: CourseAccent { workspace.accent(courseId) }

    func show(note id: UUID) {
        openNote = id
        section = .notes
    }

    /// Takes a search result meant for this course. Returns whether it is used up; a material target is left for
    /// MaterialsView, which opens the file and then clears it.
    func follow(_ target: SearchTarget) -> Bool {
        guard target.courseId == courseId else { return false }
        section = target.section
        if let note = target.noteId { openNote = note }
        return target.materialId == nil
    }

    // MARK: Course column

    func recent(_ file: CourseFile) -> [Session] {
        Array(file.sessions.filter { $0.date <= .now && !$0.isCancelled }.sorted { $0.date > $1.date }.prefix(4))
    }

    func recentTitle(_ s: Session, in file: CourseFile) -> String {
        s.topic.isEmpty ? file.name(of: s) : "\(file.name(of: s)) · \(s.topic)"
    }

    func recentDetail(_ s: Session, in file: CourseFile) -> String {
        s.date.formatted(.dateTime.month().day().weekday()) + " · " + noteState(s, in: file)
    }

    func noteState(_ session: Session, in file: CourseFile) -> String {
        if session.reviewNoteId != nil { return String(localized: session.reviewNoteUnfinished ? .courseReviewNoteDraft : .courseReviewNote) }
        if session.roughNoteId != nil { return String(localized: .sessionsRoughNote) }
        return String(localized: file.needsReviewNote(session, at: .now) ? .courseReviewNoteMissing : .courseReviewNotNeeded)
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

    func skipReview(_ unit: FolioDomain.Unit) { workspace.skipReviews([(courseId, unit.id)]) }

    func stats(_ file: CourseFile, reviews: [Workspace.ReviewEntry], suggested: Workspace.SuggestedSession?, now: Date) -> [StatStrip.Item] {
        // A class the timetable promises counts before it is made; without it a course that makes sessions as it goes
        // never showed a next class.
        let made: (date: Date, name: String)? = file.sessions.filter { $0.date > now && !$0.isCancelled }.min { $0.date < $1.date }
            .map { (date: $0.date, name: file.name(of: $0)) }
        let planned: (date: Date, name: String)? = suggested.flatMap { $0.suggestion.date > now ? (date: $0.suggestion.date, name: $0.name) : nil }
        let nextClass = [made, planned].compactMap { $0 }.min { $0.date < $1.date }
        let nextExam = file.exams.compactMap { e in e.start.map { (e, $0) } }.filter { $0.1 > now }.min { $0.1 < $1.1 }
        let nextDue = file.assignments.compactMap { a in a.due.map { (a, $0) } }
            .filter { $0.1 > now && $0.0.status.isOpen }.min { $0.1 < $1.1 }
        let maxOverdue = reviews.map(\.item.overdueDays).max() ?? 0

        var items: [StatStrip.Item] = []
        if let next = nextClass {
            // The weekday rides in the detail: with it the date was cut off in a narrow window.
            items.append(.init(title: String(localized: .courseNextClass), value: next.date.formatted(.dateTime.month().day()),
                               detail: "\(next.date.formatted(.dateTime.weekday())) \(next.date.formatted(date: .omitted, time: .shortened)) · \(next.name)"))
        } else {
            items.append(.init(title: String(localized: .courseNextClass), value: "-"))
        }
        if let (exam, start) = nextExam {
            let d = days(to: start)
            items.append(.init(title: String(localized: .courseNextExam), value: "\(exam.title.isEmpty ? exam.kind.label : exam.title) \(d == 0 ? "D-day" : "D-\(d)")",
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
