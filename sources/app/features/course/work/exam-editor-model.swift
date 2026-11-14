import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Observation

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

    var endsBeforeStart: Bool {
        guard let start = draft.start, let end = draft.end else { return false }
        return end <= start
    }

    var title: String { isNew ? String(localized: .examsAdd) : String(localized: .commonEditNamed(draft.title)) }
    var confirm: String { String(localized: isNew ? .commonAdd : .commonSave) }
    var disabled: Bool { draft.title.trimmingCharacters(in: .whitespaces).isEmpty || endsBeforeStart }
    var note: String? {
        guard isNew, !draft.title.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return String(localized: .examsEditorFolderNote(MaterialIntake.examFolder(title: draft.title, among: course.file.exams)))
    }
    var namePrompt: String { String(localized: .examsEditorName) }
    var units: [(unit: FolioDomain.Unit, depth: Int)] { UnitTree.outline(course.file.units) }
    var components: [(UUID?, String)] {
        [(nil, String(localized: .examsEditorNoComponent))] + course.file.components.sorted { $0.order < $1.order }.map { ($0.id, $0.name) }
    }

    func setDefaultStart() {
        draft.start = workspace.calendar.date(byAdding: .hour, value: 33, to: workspace.calendar.startOfDay(for: workspace.now))
    }

    var startMinute: Int? { draft.start.map(minute) }
    var endMinute: Int? { draft.end.map(minute) }

    private func minute(_ date: Date) -> Int {
        let c = workspace.calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

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
        draft.title = draft.title.trimmingCharacters(in: .whitespaces)
        let d = draft
        let saved =
            isNew
            ? workspace.run(
                ExamAdd(
                    id: d.id, course: course.id, title: d.title, start: d.start, end: d.end, location: d.location,
                    component: d.componentId, scope: d.scopeUnitIds, scopeText: d.scopeText, allowed: d.allowed, memo: d.memo))
            : workspace.run(
                ExamSet(
                    course: course.id, exam: d.id, title: .set(d.title), start: .set(d.start), end: .set(d.end),
                    location: .set(d.location), component: .set(d.componentId), scope: .set(d.scopeUnitIds),
                    scopeText: .set(d.scopeText), allowed: .set(d.allowed), memo: .set(d.memo)))
        return saved != nil
    }
}
