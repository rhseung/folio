import FolioActions
import FolioCore
import FolioDomain
import FolioStorage
import Foundation
import Observation

@MainActor @Observable
final class ExamsModel {
    let workspace: Workspace
    private let initial: LoadedCourse
    var editing: Exam?
    var pending: PendingAction?
    private(set) var notes: [UUID: UUID] = [:]

    init(workspace: Workspace, course: LoadedCourse) {
        self.workspace = workspace
        initial = course
    }

    var course: LoadedCourse { workspace.course(initial.id) ?? initial }
    var today: LocalDate { workspace.today }

    func load() {
        let notes = (try? course.store.notes()) ?? []
        self.notes = Dictionary(
            notes.compactMap { n in
                guard n.meta.kind == .examSummary, let exam = n.meta.examId, let note = n.meta.id else { return nil }
                return (exam, note)
            }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: Page

    func exams(now: Date) -> (coming: [Exam], past: [Exam]) {
        let exams = course.file.exams.sorted { ($0.start ?? .distantFuture, $0.title) < ($1.start ?? .distantFuture, $1.title) }
        let over = { (e: Exam) in e.isOver(now: now, today: self.today, calendar: self.workspace.calendar) }
        return (exams.filter { !over($0) }, Array(exams.filter(over).reversed()))
    }

    func subtitle(coming: Int, past: Int) -> String {
        if coming + past == 0 { return String(localized: .examsEmptySubtitle) }
        return
            ([String(localized: coming == 0 ? .examsNoneComing : .examsComingCount(coming))]
            + (past == 0 ? [] : [String(localized: .examsPastCount(past))])).joined(separator: " · ")
    }

    var study: CourseStudy? { workspace.study(of: course.id) }

    func add() {
        let start = workspace.settings.schedule.examStart(after: workspace.now, calendar: workspace.calendar)
        editing = Exam(device: workspace.device, at: .now, title: "", start: start)
    }

    func folder(of exam: Exam) -> String? { MaterialIntake.folder(of: exam) }

    func drop(_ urls: [URL], on exam: Exam) {
        if let folder = folder(of: exam) { workspace.importFiles(urls, into: folder, course: course.id) }
    }

    func fileCount(_ exam: Exam) -> Int {
        course.file.materials(for: exam).filter { $0.status != .ignored }.count
    }

    func linkedMaterials(_ exam: Exam) -> [FolioDomain.Material] {
        course.file.materials(of: .exam(exam.id))
            .filter { $0.routes.contains(.direct) && !$0.routes.contains(.folder) && $0.material.status != .ignored }
            .map(\.material)
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    func materialMenu(_ exam: Exam) -> [(id: UUID, label: String, on: Bool)] {
        let file = course.file
        return file.materials
            .filter { $0.status != .ignored && $0.status != .missing && !file.routes(of: $0, to: .exam(exam.id)).contains(.folder) }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            .map { (id: $0.id, label: $0.path, on: $0.examIds.contains(exam.id)) }
    }

    func toggle(material: UUID, in exam: Exam) {
        let linked = course.file.materials.first { $0.id == material }?.examIds.contains(exam.id) ?? false
        workspace.run(MaterialLinkExam(course: course.id, material: material, exam: exam.id, linked: !linked))
    }

    func folderDetail(_ exam: Exam) -> String {
        let count = fileCount(exam)
        return String(localized: count == 0 ? .examsFolderDropHint : .examsFileCount(count))
    }

    func days(to date: Date) -> Int { max(workspace.days(to: date), 0) }

    func when(_ exam: Exam) -> (date: String, time: String?) {
        guard let start = exam.start else { return (String(localized: .examsNoDate), nil) }
        let weekday = start.formatted(.dateTime.weekday())
        guard DateTimeText.hasTime(start, calendar: workspace.calendar) else { return (start.formatted(.dateTime.month().day()), weekday) }
        let time = exam.end.map { TimePicker.range(minute(start), minute($0)) } ?? TimePicker.label(minute(start))
        return (start.formatted(.dateTime.month().day()), weekday + " " + time)
    }

    private func minute(_ date: Date) -> Int { workspace.calendar.minuteOfDay(date) }

    struct Scope {
        var units: [FolioDomain.Unit]
        var tops: [(unit: FolioDomain.Unit, children: Int)]
        var ready: Int
        var readiness: [UUID: UnitReadiness]
    }

    func scope(_ exam: Exam) -> Scope {
        let units = course.file.scopeUnits(of: exam)
        let ids = Set(units.map(\.id))
        let tops = units.filter { $0.parentId.map { !ids.contains($0) } ?? true }
        let readiness = Dictionary(uniqueKeysWithValues: units.compactMap { u in study.map { (u.id, $0.readiness(of: u.id)) } })
        return Scope(
            units: units, tops: tops.map { u in (u, units.filter { $0.parentId == u.id }.count) },
            ready: readiness.values.filter { $0.state == .ready }.count, readiness: readiness)
    }

    func scopeLine(_ exam: Exam, units: Int) -> String {
        let edited = course.file.isEdited(scopeOf: exam) ? " · " + String(localized: .examsScopeEdited) : ""
        if units == 0 {
            if !exam.scopeText.isEmpty { return exam.scopeText }
            return String(localized: exam.start == nil ? .examsScopeNoDate : .examsScopeNone)
        }
        return String(localized: .examsScopeUnits(units)) + edited + (exam.scopeText.isEmpty ? "" : " · \(exam.scopeText)")
    }

    var canPickScope: Bool { !course.file.units.isEmpty }

    func component(of exam: Exam) -> String? {
        exam.componentId.flatMap { id in course.file.components.first { $0.id == id }?.name }
    }

    func pastFacts(_ exam: Exam) -> String {
        let scoped = course.file.scope(of: exam).count
        let plan = exam.plan.filter { !$0.isRemoved }
        let checked = plan.filter { study?.isDone($0) ?? false }.count
        let files = fileCount(exam)
        let facts =
            (component(of: exam).map { [$0] } ?? [])
            + (scoped > 0 ? [String(localized: .examsScopeUnits(scoped))] : exam.scopeText.isEmpty ? [] : [exam.scopeText])
            + (exam.location.isEmpty ? [] : [exam.location])
            + (files > 0 ? [String(localized: .examsFileCount(files))] : [])
            + (plan.isEmpty ? [] : [String(localized: .examsPlanFacts(checked, plan.count))])
        return facts.joined(separator: " · ")
    }

    func summaryTitle(_ exam: Exam) -> String {
        String(localized: notes[exam.id] == nil ? .examsSummaryMake : .examsSummaryOpen)
    }

    func summaryHelp(_ exam: Exam) -> String {
        String(localized: notes[exam.id] == nil ? .examsSummaryMakeHelp : .examsSummaryOpenHelp)
    }

    func openSummary(_ exam: Exam) -> UUID? {
        guard let id = workspace.run(ExamSummary(course: course.id, exam: exam.id))?.made else { return nil }
        notes[exam.id] = id
        return id
    }
}
