import FolioActions
import FolioDomain
import SwiftUI

struct CardMenu: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.itemSheets) private var sheets
    let courseId: UUID
    let card: QuizCard
    var solveWrong: (() -> Void)?

    var body: some View {
        ItemMenu(source: CardMenuSource(workspace: workspace, courseId: courseId, card: card, solveWrong: solveWrong, sheets: sheets))
    }
}
