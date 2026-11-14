import FolioDomain
import SwiftUI

#if os(macOS)
import AppKit
#endif

struct UpdateSheet: View {
    let summary: PatchNotes.Summary
    let calendar: Calendar
    let open: @MainActor (AppLink) -> Void
    @Environment(\.dismiss) private var dismiss

    static let width: CGFloat = 460
    static let mark: CGFloat = 44
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

extension View {
    func whatsNewPrompt(_ workspace: Workspace, open: @escaping @MainActor (AppLink) -> Void) -> some View {
        modifier(WhatsNewPrompt(workspace: workspace, open: open))
    }
}
