import FolioActions
import FolioDomain
import FolioStorage
import SwiftUI

struct NoteMenu: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.openLink) private var openLink
    @Environment(\.itemSheets) private var sheets
    let courseId: UUID
    let note: NoteFile
    var host: MenuHost = .elsewhere
    var moves: MoveUndo?
    var open: (@MainActor () -> Void)?
    var build: (@MainActor () -> Void)?
    var canBuild = true
    var removed: (@MainActor () -> Void)?
    var save: (@MainActor () -> Void)?

    var body: some View {
        ItemMenu(
            source: NoteMenuSource(
                workspace: workspace, courseId: courseId, note: note, host: host, moves: moves, open: open, build: build,
                canBuild: canBuild, removed: removed, save: save, openLink: openLink, sheets: sheets))
    }
}
