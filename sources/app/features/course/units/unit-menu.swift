import FolioActions
import FolioDomain
import SwiftUI

struct UnitMenu: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.openLink) private var openLink
    @Environment(\.itemSheets) private var sheets
    let courseId: UUID
    let unitId: UUID
    var host: MenuHost = .elsewhere

    var body: some View {
        if let unit = workspace.course(courseId)?.file.units.first(where: { $0.id == unitId }) {
            ItemMenu(
                source: UnitMenuSource(workspace: workspace, courseId: courseId, unit: unit, host: host, openLink: openLink, sheets: sheets)
            )
        }
    }
}
