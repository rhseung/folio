import FolioActions
import FolioDomain
import Foundation
import Observation

// 반쯤 입력한 값(`8.`)이 되돌아가지 않도록 숫자를 입력한 글 그대로 둔다.
@MainActor @Observable
final class ScoreEntryModel {
    let workspace: Workspace
    let course: LoadedCourse
    let entry: ScoreEntry
    let isNew: Bool
    var pending: PendingAction?
    var componentId: UUID
    var title: String
    var score: String
    var max: String
    var mean: String
    var stdDev: String
    var excused: Bool
    private(set) var source: ScoreSource

    init(workspace: Workspace, course: LoadedCourse, entry: ScoreEntry) {
        self.workspace = workspace
        self.course = course
        self.entry = entry
        isNew = !course.file.scores.contains { $0.id == entry.id }
        componentId = entry.componentId
        title = entry.title
        score = isNew ? "" : entry.score.formatted(.number.grouping(.never))
        max = entry.max.formatted(.number.grouping(.never))
        mean = entry.mean?.formatted(.number.grouping(.never)) ?? ""
        stdDev = entry.stdDev?.formatted(.number.grouping(.never)) ?? ""
        excused = entry.excused
        source = entry.source
    }

    var sourceOptions: [PickOption<ScoreSource>] {
        let file = course.file
        let assignments = String(localized: .scoreSheetSourceAssignments), exams = String(localized: .scoreSheetSourceExams)
        return [PickOption(id: ScoreSource.none, title: String(localized: .scoreSheetSourceNone))]
            + file.scoreSources(for: componentId).map { s in
                let taken = file.hasScore(s, in: componentId, other: entry.id)
                let section: String = if case .exam = s { exams } else { assignments }
                return PickOption(
                    id: s, title: file.title(of: s) ?? "", detail: taken ? String(localized: .scoreSheetSourceTaken) : nil,
                    section: section, disabled: taken)
            }
    }

    func pick(_ s: ScoreSource) {
        source = s
        if title.trimmingCharacters(in: .whitespaces).isEmpty, let name = course.file.title(of: s) { title = name }
    }

    private var links: (exam: UUID?, assignment: UUID?) {
        switch source {
        case .none: (nil, nil)
        case .assignment(let a): (nil, a)
        case .exam(let e): (e, nil)
        }
    }

    var sheetTitle: String { String(localized: isNew ? .scoreSheetAdd : .scoreSheetEdit) }
    var confirmTitle: String { String(localized: isNew ? .commonAdd : .commonSave) }

    var valid: Bool {
        Double(score) != nil && (Double(max) ?? 0) > 0 && (mean.isEmpty || Double(mean) != nil) && (stdDev.isEmpty || Double(stdDev) != nil)
    }

    var hasTitle: Bool { course.file.components.first { $0.id == componentId }?.aggregation != .single }

    var componentOptions: [(UUID, String)] { course.file.components.sorted { $0.order < $1.order }.map { ($0.id, $0.name) } }

    var meanDetail: String {
        let s = Double(score)
        let z = s.flatMap { s in Double(mean).flatMap { mu in Double(stdDev).flatMap { $0 > 0 ? (s - mu) / $0 : nil } } }
        let gap = s.flatMap { s in Double(mean).map { s - $0 } }
        return z.map(\.sigmas) ?? gap.map { String(localized: .scoreSheetGapNoStdDev($0.points)) } ?? String(localized: .scoreSheetMeanHint)
    }

    func confirm() -> Bool {
        guard let s = Double(score), let m = Double(max) else { return false }
        let saved =
            isNew
            ? workspace.run(
                ScoreAdd(
                    id: entry.id, course: course.id, component: componentId, title: title, score: s, max: m,
                    mean: Double(mean), stdDev: Double(stdDev), date: entry.date, exam: links.exam, assignment: links.assignment,
                    excused: excused))
            : workspace.run(
                ScoreSet(
                    course: course.id, score: entry.id, component: .set(componentId), title: .set(title), value: .set(s), max: .set(m),
                    mean: .set(Double(mean)), stdDev: .set(Double(stdDev)), exam: .set(links.exam), assignment: .set(links.assignment),
                    excused: .set(excused)))
        return saved != nil
    }

    func remove(then done: @escaping @MainActor () -> Void) {
        pending = workspace.ask(ScoreRemove(course: course.id, score: entry.id)) { _ in done() }
    }
}
