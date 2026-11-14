import FolioActions
import FolioDomain
import SwiftUI

struct ProblemSetMenu: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.openLink) private var openLink
    @Environment(\.itemSheets) private var sheets
    let courseId: UUID
    let set: ProblemSet

    var body: some View {
        ItemMenu(source: ProblemSetMenuSource(workspace: workspace, courseId: courseId, set: set, openLink: openLink, sheets: sheets))
    }
}
