import FolioDomain
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// The sheet the first launch after an update shows once (#415), when a version since the last look brings a new
/// feature: everything those versions brought, and the page for all of it.
struct UpdateSheet: View {
    let summary: PatchNotes.Summary
    let calendar: Calendar
    let open: @MainActor (AppLink) -> Void
    @Environment(\.dismiss) private var dismiss

    static let width: CGFloat = 460
    static let mark: CGFloat = 44
    /// About six rows; a row cut at the bottom edge, under the fade, says the list goes on.
    static let listHeight: CGFloat = 264

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            VStack(spacing: Theme.Space.xxs) {
                Image(systemName: "sparkles")
                    .font(Theme.Typeface.columnTitle)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: Self.mark, height: Self.mark)
                    .background(Color.accentColor.opacity(Theme.Opacity.tint), in: .rect(cornerRadius: Theme.Radius.card))
                    .padding(.bottom, Theme.Space.s)
                Text(.whatsNewTitle).font(Theme.Typeface.columnTitle)
                Text(summary.subtitle(calendar: calendar)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
            }
            .frame(maxWidth: .infinity)
            PatchNoteList(items: summary.items, maxHeight: Self.listHeight, opening: { dismiss() })
                .environment(\.openLink, OpenLinkAction { link, _, _ in open(link) })
            buttons.frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(Theme.Space.xl)
        #if os(macOS)
        .frame(width: Self.width)
        .onExitCommand { dismiss() }
        #else
        .presentationSizing(.form)
        #endif
        .background(Theme.Palette.page)
        .font(Theme.Typeface.body)
        .controlSize(.large)
    }

    var buttons: some View {
        HStack(spacing: Theme.Space.s) {
            Button(.whatsNewSeeAll) {
                dismiss()
                open(.place(.whatsNew))
            }
            .buttonStyle(.ghost)
            Button(.commonOk) { dismiss() }
                .buttonStyle(.prominent)
                .keyboardShortcut(.defaultAction)
        }
        .fixedSize()
    }
}

/// Every window checks as the minute turns and as a class or a recording ends; one window shows the sheet: the one in
/// front, or the first to see it while the app is behind, as a class's start does (`ClassStartPrompt`).
struct WhatsNewPrompt: ViewModifier {
    let workspace: Workspace
    let open: @MainActor (AppLink) -> Void
    @State private var showing: PatchNotes.Summary?
    #if os(macOS)
    @Environment(\.appearsActive) private var active
    #endif

    struct Moment: Equatable {
        var minute: Date
        var waits: Bool
    }

    func body(content: Content) -> some View {
        content
            .task(id: Moment(minute: workspace.liveNow, waits: workspace.updateSheetWaits)) {
                await workspace.releaseNotes.check(busy: workspace.updateSheetWaits)
            }
            .onChange(of: workspace.releaseNotes.ask) { take() }
            #if os(macOS)
            // A window opened at launch is active only after the first check, which then had no window to take it.
            .onChange(of: active) { take() }
            #endif
            // However it closes (확인, 모두 보기, a row's 열기, Esc, a swipe on the iPad), the update is seen.
            .sheet(isPresented: Binding(get: { showing != nil }, set: { if !$0 { showing = nil } }),
                   onDismiss: { workspace.releaseNotes.markSeen() }) {
                if let showing { UpdateSheet(summary: showing, calendar: workspace.calendar, open: open) }
            }
    }

    func take() {
        guard workspace.releaseNotes.ask != nil else { return }
        #if os(macOS)
        guard active || !NSApp.isActive else { return }
        #endif
        showing = workspace.releaseNotes.take()
    }
}

extension View {
    func whatsNewPrompt(_ workspace: Workspace, open: @escaping @MainActor (AppLink) -> Void) -> some View {
        modifier(WhatsNewPrompt(workspace: workspace, open: open))
    }
}
