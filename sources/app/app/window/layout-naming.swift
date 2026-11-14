import FolioDomain
import SwiftUI

struct LayoutNaming: ViewModifier {
    let workspace: Workspace
    @Binding var panes: TabPanes?
    @State private var name = ""

    func body(content: Content) -> some View {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        content
            .alert(String(localized: .panesPresetsSaveTitle), isPresented: Binding(get: { panes != nil }, set: { if !$0 { panes = nil } }))
        {
            TextField(String(localized: .panesPresetsNameField), text: $name)
            Button(String(localized: .commonSave)) {
                if let panes { workspace.saveLayout(of: panes, name: trimmed) }
                panes = nil
            }
            .disabled(trimmed.isEmpty)
            Button(String(localized: .commonCancel), role: .cancel) { panes = nil }
        } message: {
            Text(.panesPresetsSaveMessage)
        }
            .onChange(of: panes != nil) { _, asking in if asking { name = workspace.newPresetName } }
    }
}
