import FolioActions
import FolioCore
import FolioDomain
import FolioStorage
import Foundation
import Observation

@MainActor @Observable
final class UnitsModel {
    // 단원 행 하나가 그릴 값이다. 둘째 줄은 낱말 조각으로 두고 오답 수만 따로 위험색으로 그린다.
    struct Row: Identifiable {
        var unit: FolioDomain.Unit
        var depth: Int
        var parts: [String]
        var wrong: String?
        var pages: [Bool]
        var readiness: UnitReadiness
        var id: UUID { unit.id }
    }

    struct ExamCard {
        var exam: Exam
        var days: Int
        var readiness: ExamReadiness
        var line: String
        var few: FewProblems?
    }

    // 범위의 문제 부족 단원을 한 줄로 모은다. 단원마다 줄을 두면 범위가 넓은 시험에서 같은 경고가 단원 수만큼 쌓인다.
    // 단원마다의 상태는 아래 범위 목록의 표시가 보인다.
    struct FewProblems {
        var units: [UUID]
        var title: String
        var detail: String
        var missing: Int
    }

    // "그 밖의 단원"의 소제목 하나다. 지난 시험마다, 시험에 없는 단원, 아직 안 배운 단원의 차례다.
    struct UnitSection: Identifiable {
        // 지난 시험의 제목은 서로 달라야 하지 않으므로 소제목 문구가 아니라 묶음 종류로 가린다.
        var kind: UnitGroup.Kind
        var title: String
        var rows: [Row]
        var id: UnitGroup.Kind { kind }
    }

    let workspace: Workspace
    let courseId: UUID
    var newTitle = ""
    var otherOpen = false
    var openUnit: UUID?
    var pending: PendingAction?
    var name = ""
    private(set) var notes: [NoteFile] = []
    private(set) var noteCounts: [UUID: Int] = [:]
    private(set) var changedCards: Set<UUID> = []

    init(workspace: Workspace, courseId: UUID) {
        self.workspace = workspace
        self.courseId = courseId
    }

    var today: LocalDate { workspace.today }
    var study: CourseStudy? { workspace.study(of: courseId) }
    var file: CourseFile? { workspace.course(courseId)?.file }

    func loadNoteCounts() {
        let all = (workspace.course(courseId).flatMap { try? $0.store.notes() }) ?? []
        var counts: [UUID: Int] = [:]
        for note in all { for unit in note.meta.unitIds { counts[unit, default: 0] += 1 } }
        noteCounts = counts
        changedCards = workspace.changedCardSources(in: courseId)
    }

    // MARK: The list

    func subtitle(_ file: CourseFile) -> String {
        let done = file.units.filter(\.isDone).count
        let unlinked = file.sessionsNeedingUnits(at: workspace.now).count
        return
            ([String(localized: .unitsCount(file.units.count)), String(localized: .unitsDoneCount(done))]
            + (unlinked == 0 ? [] : [String(localized: .unitsUnlinkedCount(unlinked))])).joined(separator: " · ")
    }

    var nextExam: Exam? { study?.nextExam(now: workspace.now, calendar: workspace.calendar) }

    func examCard(_ exam: Exam) -> ExamCard? {
        guard let study, let start = exam.start else { return nil }
        let r = study.readiness(for: exam)
        let line = [
            String(localized: .unitsExamReady(r.ready, r.units)), String(localized: .unitsExamDone(r.done, r.units)),
            String(localized: .unitsExamSolved(r.problemsTotal, r.problemsSolved)),
        ].joined(separator: " · ")
        let units = r.fewProblems.compactMap { id in study.file.units.first { $0.id == id } }
        var few: FewProblems?
        if let first = units.first {
            let count = study.problems(of: first.id).count
            let title =
                units.count > 1
                ? String(localized: .unitsFewProblemsMany(units.count))
                : String(localized: count == 0 ? .unitsFewProblemsNone(first.title) : .unitsFewProblems(first.title, count))
            let detail =
                units.count > 1 ? units.map(\.title).joined(separator: ", ") : String(localized: .unitsFewProblemsDetail)
            few = FewProblems(
                units: units.map(\.id), title: title, detail: detail, missing: units.map { study.missingProblems(of: $0.id) }.reduce(0, +))
        }
        return ExamCard(exam: exam, days: max(workspace.days(to: start), 0), readiness: r, line: line, few: few)
    }

    func examTone(_ days: Int) -> Tone {
        ExamUrgency(days: days, settings: workspace.settings.urgency) <= .soon ? .danger : .accent
    }

    func rows(in exam: Exam?) -> (scope: [Row], rest: [Row]) {
        guard let study else { return ([], []) }
        let outline = UnitTree.outline(study.file.units)
        let scoped = Set(exam.map { study.file.scope(of: $0) } ?? [])
        let all = outline.map { row(row: $0, study: study) }
        guard exam != nil else { return ([], all) }
        return (all.filter { scoped.contains($0.unit.id) }, all.filter { !scoped.contains($0.unit.id) })
    }

    func otherSections(_ exam: Exam, rest: [Row]) -> [UnitSection] {
        guard let file else { return [] }
        let byId = Dictionary(rest.map { ($0.unit.id, $0) }, uniquingKeysWith: { a, _ in a })
        return file.unitGroups(besides: exam, now: workspace.now).compactMap { group in
            let title: String
            switch group.kind {
            case .exam(let id):
                guard let past = file.exams.first(where: { $0.id == id }) else { return nil }
                title = String(localized: .unitsScope(past.title))
            case .untested: title = String(localized: .unitsOtherUntested)
            case .untaught: title = String(localized: .unitsOtherUntaught)
            }
            return UnitSection(kind: group.kind, title: title, rows: group.unitIds.compactMap { byId[$0] })
        }
    }

    func otherSummary(_ sections: [UnitSection]) -> String {
        sections.map { String(localized: .unitsGroupCount($0.title, $0.rows.count)) }.joined(separator: " · ")
    }

    private func row(row: (unit: FolioDomain.Unit, depth: Int), study: CourseStudy) -> Row {
        let p = study.progress(of: row.unit, notes: noteCounts[row.unit.id] ?? 0)
        var parts: [String] = []
        if p.pagesTotal > 0 { parts.append(String(localized: .unitsLinePages(p.pagesSeen, p.pagesTotal))) }
        if p.notes > 0 { parts.append(String(localized: .unitsLineNotes(p.notes))) }
        parts.append(String(localized: .unitsLineProblems(p.problemsSolved, p.problemsTotal)))
        if p.cardsTotal > 0 { parts.append(String(localized: .unitsLineCards(p.cardsTotal))) }
        if p.readiness.pastExam > 0 { parts.append(String(localized: .unitsLinePastExam(p.readiness.pastExam))) }
        return Row(
            unit: row.unit, depth: row.depth, parts: parts,
            wrong: p.problemsWrong > 0 ? String(localized: .unitsLineWrong(p.problemsWrong)) : nil, pages: study.pageMarks(of: row.unit),
            readiness: p.readiness)
    }

    func toggleDone(_ unit: FolioDomain.Unit) {
        workspace.run(UnitDone(course: courseId, unit: unit.id, done: !unit.isDone))
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
        file.sessions(of: unit.id).sorted { $0.date < $1.date }
    }

    func open(_ unit: FolioDomain.Unit) {
        name = unit.title
        loadNotes(unit)
    }

    func loadNotes(_ unit: FolioDomain.Unit) { notes = workspace.notes(for: unit, in: courseId) }

    func otherNotes(_ unit: FolioDomain.Unit, in file: CourseFile) -> [NoteFile] {
        let classNotes = Set(sessions(of: unit, in: file).flatMap { [$0.roughNoteId, $0.reviewNoteId].compactMap { $0 } })
        return notes.filter { $0.meta.id.map(classNotes.contains) != true }
    }

    // MARK: The open unit's study

    struct ProblemRow: Identifiable {
        var record: CourseStudy.ProblemRecord
        var title: String
        var detail: String
        var chip: (text: String, tone: Tone)?
        var id: UUID { record.problem.id }
    }

    struct CardLine: Identifiable {
        var record: CourseStudy.CardRecord
        var detail: String
        var chip: (text: String, tone: Tone)?
        var changed: Bool
        var id: UUID { record.card.id }
    }

    struct LectureRow: Identifiable {
        var material: FolioDomain.Material
        var range: ClosedRange<Int>
        var seen: [Bool]
        var id: String { "\(material.id)-\(range.lowerBound)" }
        var firstUnseen: Int { range.lowerBound + (seen.firstIndex(of: false) ?? 0) }
    }

    func readinessLine(_ r: UnitReadiness) -> String {
        let bar = String(localized: .unitReadinessBar(workspace.settings.study.readyPercent))
        guard let score = r.score else { return r.state.label + " · " + bar }
        return String(localized: .unitReadinessScore(Int((score * 100).rounded()))) + " · " + bar
    }

    func readinessDetail(_ unit: FolioDomain.Unit) -> String {
        guard let study else { return "" }
        let records = study.problems(of: unit.id)
        let right = records.filter { $0.last?.verdict == .correct }.count
        let r = study.readiness(of: unit.id)
        return [
            String(localized: .unitReadinessProblems(records.count)), String(localized: .unitReadinessRight(right)),
            String(localized: .unitReadinessWrong(r.wrong)), String(localized: .unitReadinessRecheck(r.recheck)),
            String(localized: .unitReadinessUntried(records.count - r.judged)), String(localized: .unitReadinessPastExam(r.pastExam)),
        ].joined(separator: " · ")
    }

    func conceptRows(_ r: UnitReadiness, in file: CourseFile) -> [(material: FolioDomain.Material, pages: [Int])] {
        Dictionary(grouping: r.conceptPages, by: \.materialId).compactMap { id, pages in
            file.materials.first { $0.id == id }.map { (material: $0, pages: pages.map(\.page).sorted()) }
        }
        .sorted { $0.material.path.localizedStandardCompare($1.material.path) == .orderedAscending }
    }

    static func pageList(_ pages: [Int]) -> String {
        guard let first = pages.first, let last = pages.last else { return "" }
        return pages.count > 1 && last - first == pages.count - 1 ? "\(first)–\(last)" : pages.map(String.init).joined(separator: ", ")
    }

    func lectureRows(_ unit: FolioDomain.Unit, in file: CourseFile) -> [LectureRow] {
        guard let study else { return [] }
        return unit.lecturePages.compactMap { r in
            guard let m = file.materials.first(where: { $0.id == r.materialId }) else { return nil }
            let seen = study.seenPages(of: m.id)
            return LectureRow(material: m, range: r.pages, seen: r.pages.map { seen.contains($0) })
        }
    }

    func problemRows(_ unit: FolioDomain.Unit) -> [ProblemRow] {
        guard let study else { return [] }
        return study.problems(of: unit.id).map { record in
            let set = study.file.problemSets.first { $0.id == record.setId }
            let title = String(localized: .problemsNumbered(set?.title ?? "", record.problem.number))
            var detail = [record.problem.format.label]
            if let last = record.last {
                detail.append(last.day.shortLabel)
                if let reason = last.reason { detail.append(reason.label) }
            } else {
                detail.append(String(localized: .problemsUntried))
            }
            let chip = record.status.problemChip ?? record.last.map { ($0.verdict.label, $0.verdict.tone) }
            return ProblemRow(record: record, title: title, detail: detail.joined(separator: " · "), chip: chip)
        }
    }

    func cardLines(_ unit: FolioDomain.Unit) -> [CardLine] {
        guard let study else { return [] }
        return study.cards(of: unit.id).map {
            // 참거짓 카드는 형식을 출처 앞에 적는다. 앞뒤 카드가 기본이라 따로 적지 않는다.
            let detail = ($0.card.kind == .trueFalse ? [$0.card.kind.label] : []) + [$0.card.source.label]
            return CardLine(
                record: $0, detail: detail.joined(separator: " · "), chip: $0.status.cardChip, changed: changedCards.contains($0.card.id))
        }
    }

    func lecturesNote(_ rows: [LectureRow]) -> String {
        let seen = rows.reduce(0) { $0 + $1.seen.filter { $0 }.count }, total = rows.reduce(0) { $0 + $1.seen.count }
        return String(localized: .unitsLecturesNote(seen, total))
    }

    func problemsNote(_ rows: [ProblemRow]) -> String {
        let wrong = rows.filter(\.record.status.isOpen).count, recheck = rows.filter(\.record.status.isRecheck).count
        return
            ([String(localized: .problemsCount(rows.count))] + (wrong > 0 ? [String(localized: .unitsLineWrong(wrong))] : [])
            + (recheck > 0 ? [String(localized: .unitReadinessRecheck(recheck))] : [])).joined(separator: " · ")
    }

    func cardsNote(_ rows: [CardLine]) -> String {
        let unknown = rows.filter(\.record.status.needsWork).count
        return ([String(localized: .cardsCount(rows.count))] + (unknown > 0 ? [String(localized: .cardsUnknownCount(unknown))] : []))
            .joined(separator: " · ")
    }

    func studySubtitle(_ unit: FolioDomain.Unit, in file: CourseFile) -> String {
        let scopes = file.exams(scoping: unit.id).map { String(localized: .unitsScope($0.title)) }
        return (scopes + [sessionsLine(unit, in: file)]).joined(separator: " · ")
    }

    func sessionsLine(_ unit: FolioDomain.Unit, in file: CourseFile) -> String {
        let names = sessions(of: unit, in: file).map { file.day(of: $0, calendar: workspace.calendar) }
        return names.isEmpty
            ? String(localized: .unitsNoSessions)
            : names.count > 3
                ? String(localized: .unitsSessionsMore(names.prefix(3).joined(separator: ", "), names.count - 3))
                : names.joined(separator: ", ")
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
        var own: Bool
        var pages: ClosedRange<Int>? = nil
    }

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
                let (x, y) = (
                    roles.firstIndex { $0 == a.material.role } ?? roles.count, roles.firstIndex { $0 == b.material.role } ?? roles.count
                )
                return x != y ? x < y : a.material.path.localizedStandardCompare(b.material.path) == .orderedAscending
            }
    }

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

    func rename(_ unit: FolioDomain.Unit) {
        let new = name.trimmingCharacters(in: .whitespaces)
        guard !new.isEmpty, new != unit.title else { return }
        workspace.run(UnitSet(course: courseId, unit: unit.id, title: new))
    }

    func setParent(_ parent: UUID?, of unit: FolioDomain.Unit) {
        workspace.run(UnitMove(course: courseId, unit: unit.id, target: .parent(parent)))
    }

    func classTitle(_ s: Session, besides unit: FolioDomain.Unit, in file: CourseFile) -> String? { file.subject(of: s, besides: unit.id) }

    func linkMenu(_ unit: FolioDomain.Unit, in file: CourseFile) -> [(id: UUID, label: String, on: Bool)] {
        let linked = Set(file.sessions(of: unit.id).map(\.id))
        return file.linkableSessions { linked.contains($0.id) }.reversed().map {
            (id: $0.id, label: file.title(of: $0, calendar: workspace.calendar), on: linked.contains($0.id))
        }
    }

    func toggle(session: UUID, in unit: FolioDomain.Unit) {
        workspace.run(
            UnitLink(
                course: courseId, unit: unit.id, sessions: [session],
                linked: !(workspace.course(courseId)?.file.isLinked(session: session, unit: unit.id) ?? false)))
    }

    func unlink(_ session: Session, from unit: FolioDomain.Unit) {
        workspace.run(UnitLink(course: courseId, unit: unit.id, sessions: [session.id], linked: false))
    }

    func toggleScope(_ exam: Exam, unit: FolioDomain.Unit) {
        workspace.run(ExamScope(course: courseId, exam: exam.id, unit: unit.id, included: !isScoped(unit, in: exam)))
    }

    func isScoped(_ unit: FolioDomain.Unit, in exam: Exam) -> Bool {
        workspace.course(courseId)?.file.scope(of: exam).contains(unit.id) ?? false
    }

    func reviewNote(of session: Session) -> UUID? { workspace.note(.review, of: session.id, in: courseId) }
}
