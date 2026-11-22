import FolioActions
import FolioDomain
import Foundation
import Observation

@MainActor @Observable
final class ProblemsModel {
    struct Group: Identifiable {
        var set: ProblemSet
        var note: String
        var records: [CourseStudy.ProblemRecord]
        var id: UUID { self.set.id }
    }

    let workspace: Workspace
    let courseId: UUID
    var filter = SolvePick.Filter.all
    var unit: UUID?

    init(workspace: Workspace, courseId: UUID) {
        self.workspace = workspace
        self.courseId = courseId
    }

    var study: CourseStudy? { workspace.study(of: courseId) }

    var subtitle: String {
        guard let study else { return "" }
        let all = study.allProblems
        return [
            String(localized: .problemsSetCount(study.file.problemSets.count)), String(localized: .problemsCount(all.count)),
            String(localized: .problemsWrongCount(all.filter(\.status.isOpen).count)),
            String(localized: .problemsRecheckCount(all.filter(\.status.isRecheck).count)),
        ].joined(separator: " · ")
    }

    var filterOptions: [(SolvePick.Filter, String)] {
        [
            (.all, String(localized: .solveFilterAll)), (.wrong, String(localized: .solveFilterWrong)),
            (.untried, String(localized: .solveFilterUntried)),
        ]
    }

    var unitOptions: [SelectOption<UUID?>] {
        [SelectOption(id: UUID?.none, label: String(localized: .solveAllUnits))]
            + UnitTree.outline(study?.file.units ?? []).map {
                SelectOption(id: Optional($0.unit.id), label: $0.unit.title, depth: $0.depth)
            }
    }

    private var pick: SolvePick { SolvePick(filter: filter, units: unit.map { [$0] } ?? []) }

    // 거르면 맞는 문제가 없는 묶음은 숨긴다. 거르지 않으면 문제가 없는 묶음도 보여 문제를 넣을 수 있게 한다.
    var groups: [Group] {
        guard let study else { return [] }
        let pick = pick, filtered = filter != .all || unit != nil
        return study.file.problemSets.compactMap { set in
            let records = study.problems(inSet: set.id).filter(pick.matches)
            if filtered, records.isEmpty { return nil }
            let solved = records.filter(\.solved).count
            return Group(
                set: set, note: [set.source.label, String(localized: .problemsSolvedOf(solved, records.count))].joined(separator: " · "),
                records: records)
        }
    }

    var isEmpty: Bool { study?.file.problemSets.isEmpty ?? true }

    func tone(_ r: CourseStudy.ProblemRecord) -> Tone {
        switch r.status {
        case .open: .danger
        case .recheck: .warning
        case .resolved, .neverWrong: .success
        case .untried: .plain
        }
    }

    func help(_ r: CourseStudy.ProblemRecord) -> String {
        let units = r.problem.unitIds.compactMap { id in study?.file.units.first { $0.id == id }?.title }
        let status = r.status.problemChip?.text ?? (r.solved ? Verdict.correct.label : String(localized: .problemsUntried))
        return ([status] + units).joined(separator: " · ")
    }

    func solveRequest(_ group: Group? = nil) -> SolveRequest {
        SolveRequest(course: courseId, units: unit.map { [$0] } ?? [], set: group?.set.id, mode: nil)
    }

    func solveRequest(_ r: CourseStudy.ProblemRecord) -> SolveRequest {
        SolveRequest(course: courseId, set: r.setId, problems: [r.problem.id])
    }
}
