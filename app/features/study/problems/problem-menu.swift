import FolioDomain
import SwiftUI

struct ProblemMenu: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.openLink) private var openLink
    @Environment(\.itemSheets) private var sheets
    let courseId: UUID
    let set: ProblemSet
    let problem: Problem

    var body: some View {
        ItemMenu(
            source: ProblemMenuSource(
                workspace: workspace, courseId: courseId, set: set, problem: problem, openLink: openLink, sheets: sheets))
    }
}
