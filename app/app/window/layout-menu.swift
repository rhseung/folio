import FolioDomain
import SwiftUI

/// "배치 ▸" (#62, 2026-11-11 사용자, 시안 3-C): the built-in layouts, then the user's, the tab's own checked; then
/// saving the tab's panes as a layout, and the settings where the user's are named and ordered. In a tab's menu on
/// the Mac (a long press by touch), and in 보기 on both, the iPad's way to it: its windows are its tabs.
struct LayoutChoices {
    struct Choice: Identifiable {
        let preset: PanePreset
        let enabled: Bool
        let chosen: Bool
        var id: String { preset.id }
    }

    let builtIn: [Choice]
    let mine: [Choice]
    let canSave: Bool
    let apply: (PanePreset) -> Void
    let save: () -> Void
    let manage: () -> Void
}

extension Workspace {
    func layoutChoices(for panes: TabPanes, save: @escaping () -> Void, manage: @escaping () -> Void) -> LayoutChoices {
        let current = preset(of: panes)?.id
        let choice = { (preset: PanePreset) in
            LayoutChoices.Choice(preset: preset, enabled: self.layout(preset, for: panes) != nil, chosen: preset.id == current)
        }
        return LayoutChoices(builtIn: PanePreset.builtIn.map(choice), mine: settings.panePresets.map(choice), canSave: panes.count > 1,
                             apply: { [weak self] in self?.apply($0, to: panes) }, save: save, manage: manage)
    }
}

struct LayoutMenu: View {
    let choices: LayoutChoices

    var body: some View {
        Menu(String(localized: .panesPresetsMenu)) {
            Section(String(localized: .panesPresetsBuiltIn)) {
                ForEach(choices.builtIn) { item($0) }
            }
            if !choices.mine.isEmpty {
                Section(String(localized: .panesPresetsMine)) {
                    ForEach(choices.mine) { item($0) }
                }
            }
            Divider()
            Button(String(localized: .panesPresetsSave), action: choices.save).disabled(!choices.canSave)
            Button(String(localized: .panesPresetsManage), action: choices.manage)
        }
    }

    // A toggle, so the menu checks the tab's own layout; choosing it again lays the panes out afresh.
    func item(_ choice: LayoutChoices.Choice) -> some View {
        Toggle(isOn: Binding(get: { choice.chosen }, set: { _ in choices.apply(choice.preset) })) {
            Label(choice.preset.title, systemImage: choice.preset.symbol)
        }
        .disabled(!choice.enabled)
    }
}

/// The name a layout is saved under, asked once "지금 배치 저장…" is chosen.
struct LayoutNaming: ViewModifier {
    let workspace: Workspace
    @Binding var panes: TabPanes?
    @State private var name = ""

    func body(content: Content) -> some View {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        content
            .alert(String(localized: .panesPresetsSaveTitle), isPresented: Binding(get: { panes != nil }, set: { if !$0 { panes = nil } })) {
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

extension FocusedValues {
    /// The key window's "배치 ▸", for 보기.
    @Entry var layoutChoices: LayoutChoices?
}
