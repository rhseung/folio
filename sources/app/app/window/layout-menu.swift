import FolioDomain
import SwiftUI

extension Workspace {
    func layoutChoices(for panes: TabPanes, save: @escaping () -> Void, manage: @escaping () -> Void) -> LayoutChoices {
        let current = preset(of: panes)?.id
        let choice = { (preset: PanePreset) in
            LayoutChoices.Choice(preset: preset, enabled: self.layout(preset, for: panes) != nil, chosen: preset.id == current)
        }
        return LayoutChoices(
            builtIn: PanePreset.builtIn.map(choice), mine: settings.panePresets.map(choice), canSave: panes.count > 1,
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

    func item(_ choice: LayoutChoices.Choice) -> some View {
        Toggle(isOn: Binding(get: { choice.chosen }, set: { _ in choices.apply(choice.preset) })) {
            Label(choice.preset.title, systemImage: choice.preset.symbol)
        }
        .disabled(!choice.enabled)
    }
}

extension FocusedValues {
    @Entry var layoutChoices: LayoutChoices?
}
