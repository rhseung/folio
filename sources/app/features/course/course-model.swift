import FolioDomain
import Foundation
import Observation

@MainActor @Observable
final class CourseModel {
    let workspace: Workspace
    var pending: PendingAction?
    let courseId: UUID
    var section: CourseSection = .overview { didSet { if section != oldValue { settle() } } }
    var openNote: UUID? { didSet { if openNote != oldValue { settle() } } }
    private(set) var noteAnchor: AppLink.Anchor?
    var openUnit: UUID?
    private(set) var place: AppLink
    private var following = false
    var noteInsert: String?
    let noteMoves = MoveUndo()

    init(workspace: Workspace, courseId: UUID) {
        self.workspace = workspace
        self.courseId = courseId
        place = .course(courseId)
    }

    var course: LoadedCourse? { workspace.course(courseId) }

    var openRecording: Recording? {
        guard section == .sessions, place.kind == .recording else { return nil }
        return course?.file.recordings.first { $0.id == place.id }
    }
    var accent: CourseAccent { workspace.accent(courseId) }

    func show(note id: UUID) {
        openNote = id
        section = .notes
    }

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
        case .recording: section = .sessions
        case .today, .grades, .requirements, .people, .codes, .settings, .whatsNew, .proposals, .semester, .person: break
        }
    }

    var focus: UUID? {
        guard let id = place.id else { return nil }
        switch place.kind {
        case .session, .assignment, .exam, .card, .problemSet: return id
        case .note, .material, .unit, .recording, .course, .today, .grades, .requirements, .people, .codes, .settings, .whatsNew,
            .proposals, .semester,
            .person:
            return nil
        }
    }

    func moved(_ link: AppLink?) {
        guard !following else { return }
        guard let link else { return settle() }
        // 뷰어가 쪽을 알리기 전에 알린 파일은 링크가 연 쪽을 유지해야 한다.
        if link.anchor == nil, link == place.withoutAnchor { return }
        if link != place { place = link }
    }

    func resetPage() {
        settle()
    }

    private func settle() {
        guard !following else { return }
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
        if session.reviewNoteId != nil {
            return String(localized: session.reviewNoteUnfinished ? .courseReviewNoteDraft : .courseReviewNote)
        }
        if session.roughNoteId != nil { return String(localized: .sessionsRoughNote) }
        return String(localized: file.needsReviewNote(session, at: workspace.now) ? .courseReviewNoteMissing : .courseReviewNotNeeded)
    }

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

    func score(_ file: CourseFile) -> GradeCalculator.CourseScore {
        GradeCalculator.score(components: file.components, entries: file.scores)
    }
    func unclassified(_ file: CourseFile) -> [FolioDomain.Material] { file.materials.filter { $0.status == .unclassified } }
    func reviews(now: Date) -> [Workspace.ReviewEntry] { workspace.reviewQueue(now: now).filter { $0.courseId == courseId } }
    func suggested(_ course: LoadedCourse, now: Date) -> Workspace.SuggestedSession? { workspace.suggestedSession(for: course, now: now) }
    func days(to date: Date) -> Int { workspace.days(to: date) }

    func subtitle(_ file: CourseFile) -> String {
        [workspace.semester(of: file.course)?.title, Self.scheduleLine(file.course.schedule)].compactMap { $0 }.joined(separator: " · ")
    }

    func credits(_ course: Course) -> String { String(localized: .courseCredits(course.credits.formatted())) }

    static func scheduleLine(_ schedule: [ClassTime]) -> String? {
        var groups: [(key: String, days: [String])] = []
        for slot in schedule.sorted(by: { ($0.weekday, $0.startMinute) < ($1.weekday, $1.startMinute) }) {
            let key = "\(TimeMenu.range(slot.startMinute, slot.endMinute))" + (slot.room.isEmpty ? "" : " \(slot.room)")
            let day = ClassTime.weekdayNames[slot.weekday - 1]
            if let i = groups.firstIndex(where: { $0.key == key }) { groups[i].days.append(day) } else { groups.append((key, [day])) }
        }
        return groups.isEmpty ? nil : groups.map { $0.days.joined(separator: "·") + " " + $0.key }.joined(separator: ", ")
    }

    // 캘린더의 주는 일요일에 시작할 수 있으므로, 앱의 주처럼 월요일 기준으로 센다.
    func thisWeek(now: Date) -> DateInterval {
        let start = workspace.calendar.startOfWeek(containing: now)
        return DateInterval(start: start, end: workspace.calendar.date(byAdding: .day, value: 7, to: start) ?? start)
    }

    func weekSessions(_ file: CourseFile, now: Date) -> [Session] {
        let week = thisWeek(now: now)
        return file.sessions.filter { week.contains($0.date) }.sorted { $0.date < $1.date }
    }

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
        file.assignments.isEmpty
            ? nil : String(localized: .courseAssignmentsNote(file.assignments.count, file.assignments.count - openAssignments(file).count))
    }

    func glanceUnits(_ file: CourseFile, reviews: [Workspace.ReviewEntry]) -> [FolioDomain.Unit] {
        let due = reviews.compactMap { r in file.units.first { $0.id == r.item.unitId } }
        let covered = UnitTree.outline(file.units).map(\.unit).filter { u in !u.sessionIds.isEmpty && !due.contains { $0.id == u.id } }
        return Array((due + covered.suffix(8).reversed()).prefix(8))
    }

    func stats(_ file: CourseFile, reviews: [Workspace.ReviewEntry], suggested: Workspace.SuggestedSession?, now: Date) -> [StatStrip.Item]
    {
        let made: (date: Date, subject: String?)? = file.sessions.filter { $0.date > now && !$0.isCancelled }.min { $0.date < $1.date }
            .map { (date: $0.date, subject: file.subject(of: $0)) }
        let planned: (date: Date, subject: String?)? = suggested.flatMap {
            $0.suggestion.date > now ? (date: $0.suggestion.date, subject: nil) : nil
        }
        let nextClass = [made, planned].compactMap { $0 }.min { $0.date < $1.date }
        let nextExam = file.exams.compactMap { e in e.start.map { (e, $0) } }.filter { $0.1 > now }.min { $0.1 < $1.1 }
        let nextDue = file.assignments.compactMap { a in a.due.map { (a, $0) } }
            .filter { $0.1 > now && $0.0.status.isOpen }.min { $0.1 < $1.1 }
        let maxOverdue = reviews.map(\.item.overdueDays).max() ?? 0

        var items: [StatStrip.Item] = []
        if let next = nextClass {
            items.append(
                .init(
                    title: String(localized: .courseNextClass), value: next.date.formatted(.dateTime.month().day()),
                    detail: "\(next.date.formatted(.dateTime.weekday())) \(next.date.formatted(date: .omitted, time: .shortened))"
                        + (next.subject.map { " · \($0)" } ?? "")))
        } else {
            items.append(.init(title: String(localized: .courseNextClass), value: "-"))
        }
        if let (exam, start) = nextExam {
            let d = days(to: start)
            items.append(
                .init(
                    title: String(localized: .courseNextExam), value: "\(exam.title) \(d == 0 ? "D-day" : "D-\(d)")",
                    detail: start.formatted(.dateTime.month().day().weekday()), tone: d <= 7 ? .danger : .plain))
        } else {
            items.append(.init(title: String(localized: .courseNextExam), value: "-"))
        }
        items.append(
            .init(
                title: String(localized: .courseReviewToday), value: String(localized: .courseUnitsValue(reviews.count)),
                detail: maxOverdue > 0 ? String(localized: .courseMaxOverdue(maxOverdue)) : nil, tone: maxOverdue > 0 ? .warning : .plain))
        items.append(
            .init(
                title: String(localized: .courseNearestDue), value: nextDue?.0.title ?? "-",
                detail: nextDue?.1.formatted(.dateTime.month().day().weekday().hour().minute())))
        for (i, target) in [CourseSection.sessions, .exams, .units, .assignments].enumerated() {
            items[i].action = { [weak self] in self?.section = target }
        }
        return items
    }
}
