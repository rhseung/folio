import FolioDomain
import SwiftUI

/// A sheet an item menu opens. Shown by the window rather than the row that asked, so every place that shows an item
/// (Today, the ribbon, search) can edit and delete it, not only the item's own screen.
enum ItemSheet: Identifiable {
    case session(SessionSheetRequest)

    var id: UUID {
        switch self {
        case .session(let request): request.id
        }
    }
}

/// What an item menu asks of its window: a sheet, or a confirmation (`Workspace.ask`).
struct ItemSheetsAction {
    var present: @MainActor (ItemSheet) -> Void = { _ in }
    var confirm: @MainActor (PendingAction?) -> Void = { _ in }
}

extension EnvironmentValues {
    @Entry var itemSheets = ItemSheetsAction()
}

/// Shows, per window, the sheets and confirmations item menus ask for, and the class sheet a stopped recording asks
/// for. Every window watches the recorder's ask; the first that takes it clears it, so two windows don't both ask.
struct ItemSheets: ViewModifier {
    let workspace: Workspace
    /// Set inside this modifier's content, so the sheet, attached outside it, is given it again.
    let openLink: OpenLinkAction
    @State private var shown: ItemSheet?
    @State private var pending: PendingAction?
    #if os(macOS)
    @Environment(\.appearsActive) private var active
    #endif

    func body(content: Content) -> some View {
        content
            .environment(\.itemSheets, ItemSheetsAction(present: { shown = $0 }, confirm: { pending = $0 }))
            // Again for what is laid over the window (the search palette), which sits outside where the window sets it.
            .environment(\.openLink, openLink)
            .onChange(of: workspace.wrapUpAsk) { _, ask in
                guard let ask, workspace.wrapUpAsk == ask else { return }
                let request = SessionSheetRequest(course: ask.course, session: ask.session, viewed: ask.viewed, recorded: true, asked: true)
                #if os(macOS)
                // The stop button was in the key window.
                guard active else { return }
                workspace.wrapUpAsk = nil
                shown = .session(request)
                #else
                workspace.wrapUpAsk = nil
                // The recording card's popover is still going away; a sheet asked for meanwhile is dropped.
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    shown = .session(request)
                }
                #endif
            }
            .sheet(item: $shown) { sheet in
                switch sheet {
                case .session(let request): SessionSheet(workspace: workspace, request: request).environment(\.openLink, openLink)
                }
            }
            .confirming($pending)
    }
}

extension View {
    func itemSheets(_ workspace: Workspace, openLink: OpenLinkAction) -> some View {
        modifier(ItemSheets(workspace: workspace, openLink: openLink))
    }
}
