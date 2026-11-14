import FolioActions
import FolioDomain
import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#endif

struct ClassStartPrompt: ViewModifier {
    let workspace: Workspace
    let open: @MainActor (ClassStartOpening) -> Void
    let openSplit: @MainActor (PaneLayout, UUID) -> Void
    let showing: @MainActor () -> Navigator.Entry
    let bringForward: @MainActor () -> Void
    @State private var asking: ClassStartAsk?
    @Environment(\.paneMemory) private var paneMemory
    #if os(macOS)
    @Environment(\.appearsActive) private var active
    #endif

    func body(content: Content) -> some View {
        content
            .onChange(of: workspace.liveNow, initial: true) { workspace.classStartTick(at: workspace.liveNow) }
            .onChange(of: workspace.classStartAsk) { take() }
            #if os(macOS)
        // 실행할 때 열린 창은 첫 검사가 끝난 뒤에야 active가 되고, 그 검사 때는 값을 받을 창이 없었다.
        .onChange(of: active) { take() }
            #endif
            .alert(
                Text(.classStartRecordTitle), isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } }),
                presenting: asking
            ) { ask in
                Button(.classStartRecord) { workspace.recordClass(ask) }
                Button(.commonCancel, role: .cancel) {}
            } message: { ask in
                Text(ask.title)
            }
    }

    func take() {
        guard let ask = workspace.classStartAsk else { return }
        #if os(macOS)
        guard active || !NSApp.isActive else { return }
        #endif
        workspace.classStartAsk = nil
        let shown = showing()
        for opening in workspace.classStartOpenings(ask, showing: shown) { open(opening) }
        if let split = workspace.classStartSplit(ask, showing: shown) {
            openSplit(paneMemory?.memory.starting(session: ask.session) ?? split, ask.course)
        }
        if ask.front { bringForward() }
        if ask.asksRecording { asking = ask }
    }
}
