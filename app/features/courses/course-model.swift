import FolioDomain
import FolioStorage
import Foundation
import Observation

@MainActor @Observable
final class CourseModel {
    let workspace: Workspace
    var pending: PendingAction?
    let courseId: UUID
    var section: AppLink.CoursePage = .overview { didSet { if section != oldValue { settle() } } }
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

    // 열 끝의 LMS 강의실 행이다. 받을 때 이 과목을 고른 강의실만 보인다.
    var lmsRooms: [(classroom: LMSClassroom, waiting: Int)] { workspace.lmsRooms(of: courseId) }

    func show(note id: UUID) {
        openNote = id
        section = .notes
    }

    // 노트를 연 채로 노트 행을 누르면 노트 페이지의 카드 격자로 돌아간다.
    func choose(_ tab: CourseTab) {
        if section.tab != tab { section = tab.pages[0] }
        if tab.pages.contains(.notes) { openNote = nil }
    }

    // 열린 노트가 지워졌으면 노트 페이지의 카드 격자로 돌아간다.
    func openNoteFile(_ course: LoadedCourse) -> NoteFile? {
        openNote.flatMap { course.store.note(id: $0, in: course.file) }
    }

    func follow(_ entry: Navigator.Entry) {
        guard entry.course == courseId, entry.link != place else { return }
        let link = entry.link
        following = true
        defer { following = false }
        place = link
        noteAnchor = nil

        // 노트가 아닌 곳(노트 페이지 자신 포함)으로 가면 노트를 닫는다. 그래야 뒤로와 탭 경로가 카드 격자로 돌아온다.
        openNote = link.kind == .note ? link.id : nil
        if link.kind == .note { noteAnchor = link.anchor }
        if link.kind == .course {
            section = link.page ?? .overview
        } else if let page = link.kind.coursePage {
            section = page
        }
    }

    var focus: UUID? {
        place.kind.focusesRow ? place.id : nil
    }

    func moved(_ link: AppLink?) {
        guard !following else { return }
        guard let link else { return settle() }
        // 뷰어가 쪽을 알리기 전에 알린 파일은 링크가 연 쪽을 유지해야 한다.
        if link.anchor == nil, link == place.withoutAnchor { return }
        if link != place { place = link }
    }

    private func settle() {
        guard !following else { return }
        noteAnchor = nil
        if section == .notes, let openNote {
            place = AppLink(.note, openNote)
        } else {
            place = .course(courseId, page: section)
        }
    }

    // MARK: Course column

    func recent(_ file: CourseFile) -> [Session] {
        Array(file.heldSessions(at: workspace.now).sorted { $0.date > $1.date }.prefix(4))
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
        file.courseScore(at: workspace.now)
    }
    func unclassified(_ file: CourseFile) -> [FolioDomain.Material] { file.materials.filter { $0.status == .unclassified } }
    var study: CourseStudy? { workspace.study(of: courseId) }
    func suggested(_ course: LoadedCourse, now: Date) -> Workspace.SuggestedSession? { workspace.suggestedSession(for: course, now: now) }
    func days(to date: Date) -> Int { workspace.days(to: date) }

    func subtitle(_ file: CourseFile) -> String {
        [workspace.semester(of: file.course)?.title, Self.scheduleLine(file.course.schedule)].compactMap { $0 }.joined(separator: " · ")
    }

    func credits(_ course: Course) -> String { String(localized: .courseCredits(course.credits.formatted())) }

    static func scheduleLine(_ schedule: [ClassTime]) -> String? {
        var groups: [(key: String, days: [String])] = []
        for slot in schedule.sorted(by: { ($0.weekday, $0.startMinute) < ($1.weekday, $1.startMinute) }) {
            let key = "\(TimePicker.range(slot.startMinute, slot.endMinute))" + (slot.room.isEmpty ? "" : " \(slot.room)")
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

    func sessionCount(of unit: FolioDomain.Unit) -> Int { workspace.course(courseId)?.file.sessions(of: unit.id).count ?? 0 }

    // 다가오는 시험이 있으면 그 범위 단원을, 없으면 최근에 다룬 단원을 보인다.
    func glanceUnits(_ file: CourseFile, study: CourseStudy?) -> [(unit: FolioDomain.Unit, readiness: UnitReadiness?)] {
        let outline = UnitTree.outline(file.units).map(\.unit)
        let exam = study?.nextExam(now: workspace.now, calendar: workspace.calendar)
        let units =
            exam.map { file.scopeUnits(of: $0) }
            ?? Array(outline.filter { !file.sessions(of: $0.id).isEmpty }.suffix(8).reversed())
        return units.prefix(8).map { ($0, study?.readiness(of: $0.id)) }
    }

    func stats(_ file: CourseFile, study: CourseStudy?, suggested: Workspace.SuggestedSession?, now: Date) -> [StatGroup.Item] {
        let nextClass = file.nextClass(after: now, suggested: suggested.map { [$0.suggestion.date] } ?? []).map {
            (date: $0.date, subject: $0.session.flatMap { file.subject(of: $0) })
        }
        let nextExam = file.exams.compactMap { e in e.start.map { (e, $0) } }.filter { $0.1 > now }.min { $0.1 < $1.1 }
        let nextDue = file.assignments.compactMap { a in a.due.map { (a, $0) } }
            .filter { $0.1 > now && $0.0.status.isOpen }.min { $0.1 < $1.1 }
        let ready = study.flatMap { s in s.nextExam(now: now, calendar: workspace.calendar).map { s.readiness(for: $0) } }

        var items: [StatGroup.Item] = []
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
                    title: String(localized: .courseNextExam), value: "\(exam.title) \(DateTimeText.dday(days: d))",
                    detail: start.formatted(.dateTime.month().day().weekday()),
                    tone: ExamUrgency(days: d, settings: workspace.settings.urgency) <= .soon ? .danger : .plain))
        } else {
            items.append(.init(title: String(localized: .courseNextExam), value: "-"))
        }
        items.append(
            .init(
                title: String(localized: .courseReadyUnits),
                value: ready.map { String(localized: .courseReadyValue($0.ready, $0.units)) } ?? "-",
                detail: ready.map { String(localized: .unitsExamSolved($0.problemsTotal, $0.problemsSolved)) },
                tone: ready.map { $0.ready < $0.units ? .warning : .success } ?? .plain))
        items.append(
            .init(
                title: String(localized: .courseNearestDue), value: nextDue?.0.title ?? "-",
                detail: nextDue?.1.formatted(.dateTime.month().day().weekday().hour().minute())))
        for (i, target) in [AppLink.CoursePage.sessions, .exams, .units, .assignments].enumerated() {
            items[i].action = { [weak self] in self?.section = target }
        }
        return items
    }
}
