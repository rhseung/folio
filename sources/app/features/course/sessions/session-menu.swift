import FolioActions
import FolioDomain
import SwiftUI

struct SessionMenu: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.openURL) private var openURL
    @Environment(\.openLink) private var openLink
    @Environment(\.itemSheets) private var sheets
    let courseId: UUID
    let sessionId: UUID
    var host: MenuHost = .elsewhere
    let openNote: (UUID) -> Void

    var body: some View {
        if let source = SessionMenu.source(
            workspace, courseId, sessionId, host: host, openNote: openNote, openLink: openLink, openURL: openURL, sheets: sheets)
        {
            ItemMenu(source: source)
        }
    }

    @MainActor static func source(
        _ workspace: Workspace, _ courseId: UUID, _ sessionId: UUID, host: MenuHost, openNote: @escaping (UUID) -> Void,
        openLink: OpenLinkAction, openURL: OpenURLAction, sheets: ItemSheetsAction
    ) -> SessionMenuSource? {
        guard let session = workspace.course(courseId)?.file.sessions.first(where: { $0.id == sessionId }) else { return nil }
        return SessionMenuSource(
            workspace: workspace, courseId: courseId, session: session, host: host, now: workspace.liveNow,
            openNote: openNote, openLink: openLink, openURL: openURL, sheets: sheets)
    }
}
