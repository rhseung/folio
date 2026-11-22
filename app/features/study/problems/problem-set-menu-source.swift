import FolioActions
import FolioDomain
import SwiftUI

@MainActor
struct ProblemSetMenuSource: ItemMenuSource {
    let workspace: Workspace
    let courseId: UUID
    let set: ProblemSet
    let openLink: OpenLinkAction
    let sheets: ItemSheetsAction

    private var file: CourseFile? { workspace.course(courseId)?.file }

    private func material(_ id: UUID?) -> FolioDomain.Material? {
        id.flatMap { id in file?.materials.first { $0.id == id } }
    }

    var commands: [ProblemSetMenuCommand] {
        ProblemSetMenuCommand.commands(hasSheet: material(set.materialId) != nil, hasSolution: material(set.solutionMaterialId) != nil)
    }

    func row(_ command: ProblemSetMenuCommand) -> MenuRow {
        switch command {
        case .openSheet:
            MenuRow(command, .problemSetOpenSheet, "doc.richtext", .action { open(set.materialId) })
        case .openSolution:
            MenuRow(command, .problemSetOpenSolution, "checkmark.seal", .action { open(set.solutionMaterialId) })
        case .solve:
            MenuRow(
                command, .unitsSolve, "pencil.and.list.clipboard",
                .action { sheets.present(.solve(SolveRequest(course: courseId, set: set.id))) })
        case .share:
            .share(command, AppLink(.problemSet, set.id), course: courseId)
        case .remove:
            .remove(command) { sheets.confirm(workspace.ask(ProblemSetRemove(course: courseId, set: set.id))) }
        }
    }

    private func open(_ id: UUID?) {
        if let id { openLink(AppLink(.material, id), course: courseId) }
    }
}
