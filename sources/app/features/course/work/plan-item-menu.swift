import FolioActions
import FolioDomain
import FolioStorage
import SwiftUI

struct PlanItemMenu: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.itemSheets) private var sheets
    let courseId: UUID
    let examId: UUID
    let item: UUID
    let done: Bool
    let toggle: () -> Void

    var body: some View {
        ItemMenu(
            source: PlanItemMenuSource(
                workspace: workspace, courseId: courseId, examId: examId, item: item, done: done, toggle: toggle, sheets: sheets))
    }
}
