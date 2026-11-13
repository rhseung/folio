import FolioActions
import FolioDomain
import SwiftUI

struct SessionSlot: View {
    static let width: CGFloat = 56
    static var empty: some View { Color.clear.frame(width: width, height: 1) }

    let title: String
    let symbol: String
    var tint: Color = Theme.Palette.textSecondary
    let help: String
    var fixed = true
    let action: () -> Void

    init(
        _ title: String, symbol: String, tint: Color = Theme.Palette.textSecondary, help: String, fixed: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.help = help
        self.fixed = fixed
        self.action = action
    }

    var body: some View {
        Button(title, systemImage: symbol, action: action)
            .buttonStyle(.ghost)
            .tint(tint)
            .help(help)
            .frame(width: fixed ? Self.width : nil, alignment: .trailing)
    }
}

struct SessionNoteSlots: View {
    @Environment(\.accent) private var accent
    @Environment(Workspace.self) private var workspace
    let file: CourseFile
    let session: Session
    var offersRough = false
    let openNote: (UUID) -> Void
    let create: (NoteKind) -> Void

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            if let id = session.roughNoteId {
                SessionSlot(String(localized: .sessionsSlotRough), symbol: "doc.text", help: String(localized: .sessionsOpenRoughNote)) {
                    openNote(id)
                }
            } else if offersRough {
                SessionSlot(
                    String(localized: .sessionsSlotRough), symbol: "plus", tint: accent.ink,
                    help: String(localized: .sessionsSlotRoughMakeHelp)
                ) { create(.rough) }
            } else {
                SessionSlot.empty
            }
            if let id = session.reviewNoteId {
                if session.reviewNoteUnfinished {
                    SessionSlot(
                        String(localized: .sessionsSlotReview), symbol: "square.and.pencil", tint: Theme.Palette.warning,
                        help: String(localized: .sessionsSlotReviewDraftHelp)
                    ) { openNote(id) }
                } else {
                    SessionSlot(
                        String(localized: .sessionsSlotReview), symbol: "doc.text", help: String(localized: .sessionsOpenReviewNote)
                    ) { openNote(id) }
                }
            } else if file.needsReviewNote(session, at: workspace.now) {
                SessionSlot(
                    String(localized: .sessionsSlotReview), symbol: "plus", tint: Theme.Palette.warning,
                    help: String(localized: .sessionsSlotReviewMakeHelp)
                ) { create(.review) }
            } else if session.skipsReview {
                Text(.sessionsSlotNoReview).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                    .frame(width: SessionSlot.width, alignment: .trailing)
            } else {
                SessionSlot.empty
            }
        }
    }
}
