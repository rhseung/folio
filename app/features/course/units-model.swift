import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Observation

/// The units list and the unit opened from it. Review states are worked out when the page draws; quiz counts and a
/// unit's notes are read from disk, so they are loaded when what they depend on changes.
@MainActor @Observable
final class UnitsModel {
    struct QuizStats: Equatable {
        var cards = 0
        var openWrong = 0
    }

    let workspace: Workspace
    let courseId: UUID
    var newTitle = ""
    var openUnit: UUID?
    var pending: PendingAction?
    private(set) var quiz: [UUID: QuizStats] = [:]
    /// The open unit's rename field, saved when it is submitted or the unit closes.
    var name = ""
    private(set) var notes: [NoteFile] = []

    init(workspace: Workspace, courseId: UUID) {
        self.workspace = workspace
        self.courseId = courseId
    }

    var today: LocalDate { workspace.today }
    func states(now: Date? = nil) -> [UUID: ReviewState] { workspace.reviewStates(of: courseId, now: now ?? workspace.now) }

    func loadQuiz(_ course: LoadedCourse) {
        let settings = workspace.settings, calendar = workspace.calendar
        var attempts: [UUID: [(day: LocalDate, verdict: Verdict)]] = [:]
        for (at, attempt) in ((try? course.store.log.readAll()) ?? []).events(QuizAttemptEvent.self) {
            attempts[attempt.cardId, default: []].append((settings.studyDay(of: at, calendar: calendar), attempt.verdict))
        }
        var result: [UUID: QuizStats] = [:]
        for unit in course.file.units {
            let cards = (try? course.store.loadQuiz(unit: unit.id).model.cards) ?? []
            guard !cards.isEmpty else { continue }
            result[unit.id] = QuizStats(cards: cards.count, openWrong: cards.filter { WrongFlow.isOpen(WrongFlow.status(attempts[$0.id] ?? [])) }.count)
        }
        quiz = result
    }

    // MARK: The list

    func subtitle(_ file: CourseFile, states: [UUID: ReviewState]) -> String {
        let due = states.values.filter { ($0.due.map { $0 <= today }) == true }.count
        let unlinked = file.sessionsNeedingUnits(at: workspace.now).count
        return ([String(localized: .unitsCount(file.units.count)), String(localized: .unitsDueToday(due))]
                + (unlinked == 0 ? [] : [String(localized: .unitsUnlinkedCount(unlinked))])).joined(separator: " · ")
    }

    func exams(of unit: FolioDomain.Unit, in file: CourseFile) -> [Exam] { file.exams.filter { $0.scopeUnitIds.contains(unit.id) } }

    func sessionsLine(_ unit: FolioDomain.Unit, in file: CourseFile) -> String {
        let names = sessions(of: unit, in: file).map { file.day(of: $0, calendar: workspace.calendar) }
        return names.isEmpty ? String(localized: .unitsNoSessions)
            : names.count > 3 ? String(localized: .unitsSessionsMore(names.prefix(3).joined(separator: ", "), names.count - 3)) : names.joined(separator: ", ")
    }

    func detail(_ unit: FolioDomain.Unit, state: ReviewState?, in file: CourseFile) -> String {
        var parts = [sessionsLine(unit, in: file)]
        if let state, !state.settled { parts.append(String(localized: .unitsInterval(workspace.settings.review.interval(atStep: state.step)))) }
        if let q = quiz[unit.id] {
            parts.append(String(localized: .unitsQuizCards(q.cards)))
            if q.openWrong > 0 { parts.append(String(localized: .unitsWrong(q.openWrong))) }
        }
        return parts.joined(separator: " · ")
    }

    var canAdd: Bool { workspace.can(UnitAdd(course: courseId, title: newTitle)) }

    func add() {
        guard workspace.run(UnitAdd(course: courseId, title: newTitle)) != nil else { return }
        newTitle = ""
    }

    func move(_ unit: FolioDomain.Unit, by offset: Int) {
        workspace.run(UnitMove(course: courseId, unit: unit.id, target: .by(offset)))
    }

    func remove(_ unit: FolioDomain.Unit) {
        pending = workspace.ask(UnitRemove(course: courseId, unit: unit.id)) { [weak self] _ in
            if self?.openUnit == unit.id { self?.openUnit = nil }
        }
    }

    // MARK: The open unit

    func sessions(of unit: FolioDomain.Unit, in file: CourseFile) -> [Session] {
        file.sessions.filter { unit.sessionIds.contains($0.id) }.sorted { $0.date < $1.date }
    }

    func open(_ unit: FolioDomain.Unit) {
        name = unit.title
        loadNotes(unit)
    }

    func loadNotes(_ unit: FolioDomain.Unit) { notes = workspace.notes(for: unit, in: courseId) }

    /// Rough and review notes already sit in their class's row.
    func otherNotes(_ unit: FolioDomain.Unit, in file: CourseFile) -> [NoteFile] {
        let classNotes = Set(sessions(of: unit, in: file).flatMap { [$0.roughNoteId, $0.reviewNoteId].compactMap { $0 } })
        return notes.filter { $0.meta.id.map(classNotes.contains) != true }
    }

    func history(_ unit: FolioDomain.Unit) -> [(at: Date, event: ReviewEvent)] {
        workspace.reviews(of: courseId).filter { $0.event.unitId == unit.id }.reversed()
    }

    func stats(_ unit: FolioDomain.Unit, state: ReviewState?, reviews: Int) -> [StatStrip.Item] {
        let review = workspace.settings.review
        let next = state?.due.map { $0 < today ? String(localized: .unitsDaysLate($0.days(until: today))) : $0 == today ? String(localized: .unitsToday) : $0.shortLabel }
            ?? (state?.settled == true ? String(localized: .unitsReviewDone) : "-")
        let q = quiz[unit.id]
        return [
            .init(title: String(localized: .unitsNextReview), value: next, tone: (state?.due.map { $0 < today }) == true ? .danger : .plain),
            .init(title: String(localized: .unitsIntervalTitle), value: state.map { String(localized: .unitsDays(review.interval(atStep: $0.step))) } ?? "-",
                  detail: state.map { String(localized: .unitsStep($0.step + 1, review.intervals.count)) }),
            .init(title: String(localized: .unitsReviewsTitle), value: String(localized: .unitsTimes(reviews))),
            .init(title: String(localized: .unitsQuiz), value: q.map { String(localized: .unitsCards($0.cards)) } ?? "-",
                  detail: q.flatMap { $0.openWrong > 0 ? String(localized: .unitsWrong($0.openWrong)) : nil },
                  tone: (q?.openWrong ?? 0) > 0 ? .warning : .plain),
        ]
    }

    func parentPath(_ unit: FolioDomain.Unit, in file: CourseFile) -> String? {
        var titles: [String] = []
        var next = unit.parentId
        while let id = next, let parent = file.units.first(where: { $0.id == id }), titles.count < 8 {
            titles.insert(parent.title, at: 0)
            next = parent.parentId
        }
        return titles.isEmpty ? nil : titles.joined(separator: " › ")
    }

    struct MaterialRow {
        var material: FolioDomain.Material
        var detail: String
        /// Linked to the unit or holding its pages; otherwise it only comes through a class.
        var own: Bool
        /// The unit's pages of a split lecture (#321), drawn as the section strip.
        var pages: ClosedRange<Int>? = nil
    }

    /// The files that belong with the unit (`CourseFile.routes(of:to:)`), by role as on the materials page.
    func materials(_ unit: FolioDomain.Unit, in file: CourseFile) -> [MaterialRow] {
        let roles = MaterialRole.allCases
        return file.materials(of: .unit(unit.id))
            .filter { $0.material.status != .ignored }
            .map { m, routes in
                let via = Set(routes.compactMap { route -> UUID? in if case .session(let id) = route { id } else { nil } })
                let links = file.sessionLinks(of: m.id).filter { via.contains($0.session.id) }
                let role = m.status == .unclassified ? String(localized: .unitsUnclassified) : (m.role ?? .other).label
                let own = routes.contains(.direct) || routes.contains(.pages)
                let detail = [role] + links.map { file.day(of: $0.session, calendar: workspace.calendar) + $0.link.pageLabel }
                return MaterialRow(material: m, detail: detail.joined(separator: " · "), own: own, pages: file.pages(of: unit.id, in: m.id))
            }
            .sorted { a, b in
                let (x, y) = (roles.firstIndex { $0 == a.material.role } ?? roles.count, roles.firstIndex { $0 == b.material.role } ?? roles.count)
                return x != y ? x < y : a.material.path.localizedStandardCompare(b.material.path) == .orderedAscending
            }
    }

    /// Every tracked file, the linked ones marked, for the 자료 연결 picker.
    func materialMenu(_ unit: FolioDomain.Unit, in file: CourseFile) -> [(id: UUID, label: String, on: Bool)] {
        file.materials
            .filter { $0.status != .ignored && $0.status != .missing }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            .map { (id: $0.id, label: $0.path, on: $0.unitIds.contains(unit.id)) }
    }

    func toggle(material: UUID, in unit: FolioDomain.Unit, file: CourseFile) {
        let linked = file.materials.first { $0.id == material }?.unitIds.contains(unit.id) ?? false
        workspace.run(MaterialLinkUnit(course: courseId, material: material, unit: unit.id, linked: !linked))
    }

    func examsByDate(_ file: CourseFile) -> [Exam] { file.exams.sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) } }

    func studyDay(_ date: Date) -> LocalDate { workspace.settings.studyDay(of: date, calendar: workspace.calendar) }

    static func minutes(_ seconds: Int) -> String {
        String(localized: seconds < 60 ? .unitsSeconds(seconds) : .unitsMinutes(seconds / 60))
    }

    func rename(_ unit: FolioDomain.Unit) {
        let new = name.trimmingCharacters(in: .whitespaces)
        guard !new.isEmpty, new != unit.title else { return }
        workspace.run(UnitSet(course: courseId, unit: unit.id, title: new))
    }

    func setParent(_ parent: UUID?, of unit: FolioDomain.Unit) {
        workspace.run(UnitMove(course: courseId, unit: unit.id, target: .parent(parent)))
    }

    /// A class in a unit's list goes by its other units: the page already names this one.
    func classTitle(_ s: Session, besides unit: FolioDomain.Unit, in file: CourseFile) -> String? { file.subject(of: s, besides: unit.id) }

    func linkMenu(_ unit: FolioDomain.Unit, in file: CourseFile) -> [(id: UUID, label: String, on: Bool)] {
        file.linkableSessions { unit.sessionIds.contains($0.id) }.reversed().map {
            (id: $0.id, label: file.title(of: $0, calendar: workspace.calendar), on: unit.sessionIds.contains($0.id))
        }
    }

    func toggle(session: UUID, in unit: FolioDomain.Unit) {
        workspace.run(UnitLink(course: courseId, unit: unit.id, sessions: [session], linked: !unit.sessionIds.contains(session)))
    }

    func unlink(_ session: Session, from unit: FolioDomain.Unit) {
        workspace.run(UnitLink(course: courseId, unit: unit.id, sessions: [session.id], linked: false))
    }

    func toggleScope(_ exam: Exam, unit: FolioDomain.Unit) {
        workspace.run(ExamScope(course: courseId, exam: exam.id, unit: unit.id, included: !exam.scopeUnitIds.contains(unit.id)))
    }

    func reviewNote(of session: Session) -> UUID? { workspace.note(.review, of: session.id, in: courseId) }
}
