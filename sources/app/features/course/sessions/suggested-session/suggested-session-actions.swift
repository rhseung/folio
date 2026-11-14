import FolioActions
import FolioDomain
import SwiftUI

struct SuggestedSessionActions: View {
    @Environment(Workspace.self) private var workspace
    let item: Workspace.SuggestedSession
    var compact = false
    let openNote: (UUID) -> Void
    var editTimes: (() -> Void)?

    private var menu: SessionMenuModel { SessionMenuModel(workspace: workspace, courseId: item.courseId) }

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            if menu.isToday(item) {
                Button {
                    if let id = menu.roughNote(item) { openNote(id) }
                } label: {
                    if compact {
                        Image(systemName: "square.and.pencil").accessibilityLabel(Text(.sessionsRoughNote))
                    } else {
                        Text(.sessionsRoughNote)
                    }
                }
                .buttonStyle(.prominent)
                .help(Text(.sessionsRoughNoteHelp))
            } else {
                Button(.sessionsMake) { menu.make(item) }.buttonStyle(.pointing(.bordered))
            }
            Menu {
                SuggestedSessionItems(item: item, primary: false, openNote: openNote, editTimes: editTimes)
            } label: {
                Image(systemName: "ellipsis").foregroundStyle(Theme.Palette.textSecondary).frame(width: 24, height: 24).contentShape(.rect)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.borderless).pointingHand()
            .fixedSize()
            .help(Text(.sessionsSuggestionMenuHelp))
        }
    }
}
