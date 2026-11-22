import FolioActions
import FolioDomain
import Foundation
import Observation

@MainActor @Observable
final class ProblemDraftModel {
    struct Row: Identifiable {
        var problem: Problem
        var kept = true
        var id: UUID { problem.id }
    }

    let workspace: Workspace
    let course: LoadedCourse
    let material: UUID
    let draft: StudyDraft?
    var title: String
    var rows: [Row]
    var pending: PendingAction?
    // 버리기를 확인한 뒤 시트를 닫는다.
    var finished = false

    init(workspace: Workspace, course: LoadedCourse, material: UUID) {
        self.workspace = workspace
        self.course = course
        self.material = material
        let draft = ((try? course.store.drafts()) ?? []).map(\.model).first {
            $0.kind == .problems && $0.materialId == material && !$0.isApplied
        }
        self.draft = draft
        if case .string(let t)? = draft?.proposal.input["title"] { title = t } else { title = draft?.title ?? "" }
        rows = (draft?.problems ?? []).map { Row(problem: $0) }
    }

    var sheetTitle: String { String(localized: .problemDraftTitle(draft?.title ?? "")) }
    private var kept: [Problem] { rows.filter(\.kept).map(\.problem) }
    var confirmTitle: String { String(localized: .problemDraftAccept(kept.count)) }
    var canAccept: Bool { !kept.isEmpty && !title.trimmingCharacters(in: .whitespaces).isEmpty }

    var unitOptions: [SelectOption<UUID>] {
        UnitTree.outline(course.file.units).map { SelectOption(id: $0.unit.id, label: $0.unit.title, depth: $0.depth) }
    }

    func caption(_ p: Problem) -> String {
        ([p.format.label] + (p.page.map { [String(localized: .problemDraftPage($0))] } ?? [])).joined(separator: " · ")
    }

    func toggle(_ id: UUID) {
        guard let i = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[i].kept.toggle()
    }

    func accept() -> Bool {
        workspace.run(
            ProblemSetAccept(course: course.id, material: material, title: title.trimmingCharacters(in: .whitespaces), problems: kept))
            != nil
    }

    func discard() {
        pending = workspace.ask(ProblemSetDiscard(course: course.id, material: material)) { [weak self] _ in self?.finished = true }
    }
}
