import FolioActions
import FolioDomain
import FolioStorage
import SwiftUI

extension AssignmentStatus {
    static let menuOrder: [AssignmentStatus] = [.todo, .doing, .submitted, .graded]
}

struct AssignmentMenu: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.openLink) private var openLink
    @Environment(\.itemSheets) private var sheets
    let courseId: UUID
    let assignmentId: UUID
    var host: MenuHost = .elsewhere

    var body: some View {
        if let source = AssignmentMenu.source(workspace, courseId, assignmentId, host: host, openLink: openLink, sheets: sheets) {
            ItemMenu(source: source)
        }
    }

    @MainActor static func source(
        _ workspace: Workspace, _ courseId: UUID, _ id: UUID, host: MenuHost, openLink: OpenLinkAction,
        sheets: ItemSheetsAction
    ) -> AssignmentMenuSource? {
        guard let assignment = workspace.course(courseId)?.file.assignments.first(where: { $0.id == id }) else { return nil }
        return AssignmentMenuSource(
            workspace: workspace, courseId: courseId, assignment: assignment, host: host, openLink: openLink, sheets: sheets)
    }
}
