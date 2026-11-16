import Algorithms
import FolioActions
import FolioDomain
import FolioStorage
import SwiftUI

struct MaterialMenu: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.openLink) private var openLink
    @Environment(\.itemSheets) private var sheets
    let courseId: UUID
    let materialId: UUID
    var host: MenuHost = .elsewhere
    var moves: MoveUndo?
    var relink: (@MainActor () -> Void)?
    var untrack: (@MainActor () -> Void)?

    var body: some View {
        if let material = workspace.course(courseId)?.file.materials.first(where: { $0.id == materialId }) {
            ItemMenu(
                source: MaterialMenuSource(
                    workspace: workspace, courseId: courseId, material: material, host: host, moves: moves,
                    relink: relink, untrack: untrack, openLink: openLink, sheets: sheets))
        }
    }
}
