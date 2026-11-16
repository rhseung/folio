import FolioDomain
import SwiftUI

struct CourseMenu: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.openLink) private var openLink
    @Environment(\.itemSheets) private var sheets
    let courseId: UUID
    var host: MenuHost = .elsewhere

    var body: some View {
        ItemMenu(source: CourseMenuSource(workspace: workspace, courseId: courseId, host: host, openLink: openLink, sheets: sheets))
    }
}
