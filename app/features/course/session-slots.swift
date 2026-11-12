import FolioActions
import FolioDomain
import SwiftUI

/// One action of a session row: an icon and a short word, all in one plain style. Whether it exists, is offered or is
/// missing shows only in the icon and color, and the fixed width keeps each kind in one column down the page.
struct SessionSlot: View {
    // Fits an icon and two letters (and caption-sized 복습 없음) with little to spare, so neighbors sit close.
    static let width: CGFloat = 56
    static var empty: some View { Color.clear.frame(width: width, height: 1) }

    let title: String
    let symbol: String
    var tint: Color = Theme.Palette.textSecondary
    let help: String
    /// Off for the recording, which sits leftmost and lines up with nothing.
    var fixed = true
    let action: () -> Void

    init(_ title: String, symbol: String, tint: Color = Theme.Palette.textSecondary, help: String, fixed: Bool = true, action: @escaping () -> Void) {
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
            // Trailing, so the spare room falls between slots and every gap reads the same.
            .frame(width: fixed ? Self.width : nil, alignment: .trailing)
    }
}

/// The rough and review note slots, shared by the sessions page and a unit's classes so both read alike.
struct SessionNoteSlots: View {
    @Environment(\.accent) private var accent
    @Environment(Workspace.self) private var workspace
    let file: CourseFile
    let session: Session
    /// Today's class offers its rough note before it exists.
    var offersRough = false
    let openNote: (UUID) -> Void
    let create: (NoteKind) -> Void

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            if let id = session.roughNoteId {
                SessionSlot(String(localized: .sessionsSlotRough), symbol: "doc.text", help: String(localized: .sessionsOpenRoughNote)) { openNote(id) }
            } else if offersRough {
                SessionSlot(String(localized: .sessionsSlotRough), symbol: "plus", tint: accent.ink, help: String(localized: .sessionsSlotRoughMakeHelp)) { create(.rough) }
            } else {
                SessionSlot.empty
            }
            if let id = session.reviewNoteId {
                // Made but not written yet: still in the missing note's warning color.
                if session.reviewNoteUnfinished {
                    SessionSlot(String(localized: .sessionsSlotReview), symbol: "square.and.pencil", tint: Theme.Palette.warning,
                                help: String(localized: .sessionsSlotReviewDraftHelp)) { openNote(id) }
                } else {
                    SessionSlot(String(localized: .sessionsSlotReview), symbol: "doc.text", help: String(localized: .sessionsOpenReviewNote)) { openNote(id) }
                }
            } else if file.needsReviewNote(session, at: workspace.now) {
                SessionSlot(String(localized: .sessionsSlotReview), symbol: "plus", tint: Theme.Palette.warning, help: String(localized: .sessionsSlotReviewMakeHelp)) { create(.review) }
            } else if session.skipsReview {
                Text(.sessionsSlotNoReview).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                    .frame(width: SessionSlot.width, alignment: .trailing)
            } else {
                SessionSlot.empty
            }
        }
    }
}
