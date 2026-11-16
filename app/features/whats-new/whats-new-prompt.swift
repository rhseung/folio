import FolioDomain
import SwiftUI

#if os(macOS)
import AppKit
#endif

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
        // 실행할 때 연 창은 첫 확인 뒤에야 active가 되므로, 그때는 시트를 가져갈 창이 없었다.
        .onChange(of: active) { take() }
            #endif
            .sheet(
                isPresented: Binding(get: { showing != nil }, set: { if !$0 { showing = nil } }),
                onDismiss: { workspace.releaseNotes.markSeen() }
            ) {
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
