import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Observation

@MainActor @Observable
final class ExamsModel {
    let workspace: Workspace
    private let initial: LoadedCourse
    var editing: Exam?
    var removing: Exam?
    /// Summary note per exam, read once per course; opening one adds to it.
    private(set) var notes: [UUID: UUID] = [:]
    private(set) var done: Set<UUID> = []

    init(workspace: Workspace, course: LoadedCourse) {
        self.workspace = workspace
        initial = course
    }

    /// Looked up each time, so a saved change shows without the page being handed the course again.
    var course: LoadedCourse { workspace.course(initial.id) ?? initial }
    var today: LocalDate { workspace.today }

    func load() {
        let notes = (try? course.store.notes()) ?? []
        self.notes = Dictionary(notes.compactMap { n in
            guard n.meta.kind == .examSummary, let exam = n.meta.examId, let note = n.meta.id else { return nil }
            return (exam, note)
        }, uniquingKeysWith: { a, _ in a })
        done = workspace.donePlanItems(in: [course.id])
    }

    // MARK: Page

    func exams(now: Date) -> (coming: [Exam], past: [Exam]) {
        let exams = course.file.exams.sorted { ($0.start ?? .distantFuture, $0.title) < ($1.start ?? .distantFuture, $1.title) }
        let over = { (e: Exam) in e.isOver(now: now, today: self.today, calendar: self.workspace.calendar) }
        return (exams.filter { !over($0) }, Array(exams.filter(over).reversed()))
    }

    func subtitle(coming: Int, past: Int) -> String {
        if coming + past == 0 { return String(localized: .examsEmptySubtitle) }
        return ([String(localized: coming == 0 ? .examsNoneComing : .examsComingCount(coming))]
                + (past == 0 ? [] : [String(localized: .examsPastCount(past))])).joined(separator: " · ")
    }

    func reviewStates(now: Date) -> [UUID: ReviewState] { workspace.reviewStates(of: course.id, now: now) }

    func add() {
        let c = workspace.calendar
        let start = c.date(byAdding: .hour, value: 24 + 9, to: c.startOfDay(for: .now)) ?? .now
        editing = Exam(device: workspace.device, at: .now, kind: .midterm, title: "", start: start)
    }

    func remove(_ exam: Exam) { workspace.run(ExamRemove(course: course.id, exam: exam.id)) }

    func folder(of exam: Exam) -> String? { MaterialIntake.folder(of: exam, among: course.file.exams) }

    func drop(_ urls: [URL], on exam: Exam) {
        if let folder = folder(of: exam) { workspace.importFiles(urls, into: folder, course: course.id) }
    }

    func fileCount(_ folder: String) -> Int {
        course.file.materials.filter { $0.path.hasPrefix(folder + "/") && $0.status != .ignored }.count
    }

    func folderDetail(_ folder: String) -> String {
        let count = fileCount(folder)
        return String(localized: count == 0 ? .examsFolderDropHint : .examsFileCount(count))
    }

    func days(to date: Date) -> Int { max(workspace.days(to: date), 0) }

    /// Date over weekday and time.
    func when(_ exam: Exam) -> (date: String, time: String?) {
        guard let start = exam.start else { return (String(localized: .examsNoDate), nil) }
        let time = exam.end.map { TimeMenu.range(minute(start), minute($0)) } ?? TimeMenu.label(minute(start))
        return (start.formatted(.dateTime.month().day()), start.formatted(.dateTime.weekday()) + " " + time)
    }

    private func minute(_ date: Date) -> Int {
        let c = workspace.calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    struct Scope {
        var units: [FolioDomain.Unit]
        /// The scope's top units, each with how many of its sub-units are in scope too.
        var tops: [(unit: FolioDomain.Unit, children: Int)]
        var onTrack: Int
    }

    /// Sub-units count toward the meter only.
    func scope(_ exam: Exam, states: [UUID: ReviewState]) -> Scope {
        let units = UnitTree.outline(course.file.units).map(\.unit).filter { exam.scopeUnitIds.contains($0.id) }
        let ids = Set(units.map(\.id))
        let tops = units.filter { $0.parentId.map { !ids.contains($0) } ?? true }
        return Scope(units: units, tops: tops.map { u in (u, units.filter { $0.parentId == u.id }.count) },
                     onTrack: units.filter { states[$0.id]?.isOnTrack(today: today) ?? false }.count)
    }

    func scopeLine(_ exam: Exam, units: Int) -> String {
        if units == 0 { return exam.scopeText.isEmpty ? String(localized: .examsScopeNone) : exam.scopeText }
        return String(localized: .examsScopeUnits(units)) + (exam.scopeText.isEmpty ? "" : " · \(exam.scopeText)")
    }

    var canPickScope: Bool { !course.file.units.isEmpty }

    func pastFacts(_ exam: Exam) -> String {
        let scoped = exam.scopeUnitIds.count
        let checked = exam.plan.filter { done.contains($0.id) }.count
        let files = folder(of: exam).map { fileCount($0) } ?? 0
        let facts = [exam.kind.label]
            + (scoped > 0 ? [String(localized: .examsScopeUnits(scoped))] : exam.scopeText.isEmpty ? [] : [exam.scopeText])
            + (exam.location.isEmpty ? [] : [exam.location])
            + (files > 0 ? [String(localized: .examsFileCount(files))] : [])
            + (exam.plan.isEmpty ? [] : [String(localized: .examsPlanFacts(checked, exam.plan.count))])
        return facts.joined(separator: " · ")
    }

    func summaryTitle(_ exam: Exam) -> String {
        String(localized: notes[exam.id] == nil ? .examsSummaryMake : .examsSummaryOpen)
    }

    func summaryHelp(_ exam: Exam) -> String {
        String(localized: notes[exam.id] == nil ? .examsSummaryMakeHelp : .examsSummaryOpenHelp)
    }

    /// The exam's summary note, created from the template the first time.
    func openSummary(_ exam: Exam) -> UUID? {
        guard let id = workspace.run(ExamSummary(course: course.id, exam: exam.id))?.made else { return nil }
        notes[exam.id] = id
        return id
    }

    // MARK: Plan

    func plan(_ exam: Exam) -> [ExamPlanItem] { exam.plan.sorted { ($0.day, $0.title) < ($1.day, $1.title) } }

    func planLine(_ items: [ExamPlanItem]) -> String {
        items.isEmpty ? String(localized: .examsPlanHint)
            : String(localized: .examsPlanDone(items.filter { done.contains($0.id) }.count, items.count))
    }

    /// The day once per run of items, so the list reads as a timeline.
    func dayLabel(_ items: [ExamPlanItem], at i: Int) -> String {
        let day = items[i].day
        guard i == 0 || items[i - 1].day != day else { return "" }
        if day == today { return String(localized: .examsToday) }
        return day.date(in: workspace.calendar)?.formatted(.dateTime.month().day().weekday()) ?? day.description
    }

    func targetTitle(_ item: ExamPlanItem) -> String? {
        item.target.flatMap { target in course.file.units.first { $0.id == target.id }?.title }
    }

    /// Scope units first: a plan is about what the exam covers.
    func targets(_ exam: Exam) -> [PickOption<UUID?>] {
        let outline = UnitTree.outline(course.file.units)
        let scoped = outline.filter { exam.scopeUnitIds.contains($0.unit.id) }
        return [PickOption(id: UUID?.none, title: String(localized: .examsPlanNoTarget))]
            + (scoped.isEmpty ? outline : scoped).map { PickOption(id: Optional($0.unit.id), title: $0.unit.title, depth: scoped.isEmpty ? $0.depth : 0) }
    }

    var firstPlanDay: Date { today.date(in: workspace.calendar) ?? .now }

    func planItem(_ exam: Exam, title: String, day: Date, unit: UUID?) -> ExamPlanAdd {
        ExamPlanAdd(course: course.id, exam: exam.id, title: title.trimmingCharacters(in: .whitespaces), day: LocalDate(day, in: workspace.calendar), unit: unit)
    }

    func canAdd(_ item: ExamPlanAdd) -> Bool { workspace.can(item) }

    func add(_ item: ExamPlanAdd) -> Bool { workspace.run(item) != nil }

    /// Checking one appends a `plan_check` event; course.json only holds the items.
    func toggle(_ id: UUID) {
        let new = !done.contains(id)
        workspace.setPlanItem(id, done: new, course: course.id)
        if new { done.insert(id) } else { done.remove(id) }
    }

    func removePlanItem(_ id: UUID, of exam: Exam) {
        workspace.run(ExamPlanRemove(course: course.id, exam: exam.id, item: id))
    }
}

/// Adds or edits one exam on a draft; nothing is saved until confirmed.
@MainActor @Observable
final class ExamEditorModel {
    let workspace: Workspace
    private let initial: LoadedCourse
    var draft: Exam

    init(workspace: Workspace, course: LoadedCourse, exam: Exam) {
        self.workspace = workspace
        initial = course
        draft = exam
    }

    var course: LoadedCourse { workspace.course(initial.id) ?? initial }
    var isNew: Bool { !course.file.exams.contains { $0.id == draft.id } }

    /// `Midterm`, `Quiz2`: the folder name, so the record and its folder read the same.
    var defaultTitle: String {
        let number = draft.kind == .quiz ? course.file.exams.filter { $0.kind == .quiz }.count + 1 : nil
        return draft.kind.folderName(number: number) ?? draft.kind.label
    }

    var endsBeforeStart: Bool {
        guard let start = draft.start, let end = draft.end else { return false }
        return end <= start
    }

    var title: String { isNew ? String(localized: .examsAdd) : String(localized: .commonEditNamed(draft.title)) }
    var confirm: String { String(localized: isNew ? .commonAdd : .commonSave) }
    var disabled: Bool { (!isNew && draft.title.isEmpty) || endsBeforeStart }
    var note: String? { isNew ? draft.kind.folderName().map { _ in String(localized: .examsEditorFolderNote(defaultTitle)) } : nil }
    var namePrompt: String { isNew ? defaultTitle : String(localized: .examsEditorName) }
    var units: [(unit: FolioDomain.Unit, depth: Int)] { UnitTree.outline(course.file.units) }
    var components: [(UUID?, String)] {
        [(nil, String(localized: .examsEditorNoComponent))] + course.file.components.sorted { $0.order < $1.order }.map { ($0.id, $0.name) }
    }

    func setDefaultStart() {
        draft.start = workspace.calendar.date(byAdding: .hour, value: 33, to: workspace.calendar.startOfDay(for: .now))
    }

    var startMinute: Int? { draft.start.map(minute) }
    var endMinute: Int? { draft.end.map(minute) }

    private func minute(_ date: Date) -> Int {
        let c = workspace.calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// Moving the start carries the end along, so a date change keeps the exam's length.
    func setStart(_ new: Date) {
        if let old = draft.start, let end = draft.end { draft.end = end.addingTimeInterval(new.timeIntervalSince(old)) }
        draft.start = new
    }

    func setEnd(_ minute: Int?) {
        guard let start = draft.start else { return }
        draft.end = minute.flatMap { workspace.calendar.date(byAdding: .minute, value: $0, to: workspace.calendar.startOfDay(for: start)) }
    }

    func addEnd() { setEnd(min((startMinute ?? 9 * 60) + 120, 23 * 60 + 59)) }

    func apply() -> Bool {
        if draft.title.isEmpty { draft.title = defaultTitle }
        let d = draft
        let saved = isNew
            ? workspace.run(ExamAdd(id: d.id, course: course.id, title: d.title, kind: d.kind, start: d.start, end: d.end, location: d.location,
                                    component: d.componentId, scope: d.scopeUnitIds, scopeText: d.scopeText, allowed: d.allowed, memo: d.memo))
            : workspace.run(ExamSet(course: course.id, exam: d.id, title: .set(d.title), kind: .set(d.kind), start: .set(d.start), end: .set(d.end),
                                    location: .set(d.location), component: .set(d.componentId), scope: .set(d.scopeUnitIds),
                                    scopeText: .set(d.scopeText), allowed: .set(d.allowed), memo: .set(d.memo)))
        return saved != nil
    }
}
