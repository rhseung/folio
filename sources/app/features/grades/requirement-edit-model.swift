import Algorithms
import FolioActions
import FolioDomain
import Foundation
import Observation

@MainActor @Observable
final class RequirementEditModel {
    let workspace: Workspace
    var draft: RequirementCategory
    let isNew: Bool

    init(workspace: Workspace, category: RequirementCategory) {
        self.workspace = workspace
        draft = category
        isNew = category.name.isEmpty
    }

    var title: String { isNew ? String(localized: .requirementsAddCategory) : String(localized: .requirementsSheetTitle(draft.name)) }

    var parentOptions: [PickOption<UUID?>] {
        let others = workspace.requirementCatalog.categories.filter { $0.id != draft.id }.sorted { $0.name < $1.name }
        return [PickOption(id: UUID?.none, title: String(localized: .requirementsNone))]
            + Category.tree(others).map {
                PickOption(id: Optional($0.category.id), title: $0.category.name, detail: $0.category.group, depth: $0.depth)
            }
    }

    var programOptions: [(UUID?, String)] {
        let programs = workspace.transcript.graduation.programs.map(\.codeId) + [draft.programId].compactMap { $0 }
        return [(UUID?.none, String(localized: .requirementsProgramCommon))]
            + programs.uniqued().map { id in
                (
                    Optional(id),
                    workspace.catalog.codes.first { $0.id == id }.map { "\($0.prefix) \($0.department)" }
                        ?? String(localized: .requirementsUnknownCode)
                )
            }
    }

    func confirm() {
        var catalog = workspace.catalog
        if let i = catalog.categories.firstIndex(where: { $0.id == draft.id }) {
            catalog.categories[i] = draft
        } else {
            catalog.categories.append(draft)
        }
        workspace.saveCatalog(catalog)
    }

    func remove() { RequirementsModel.remove(draft, in: workspace) }
}
