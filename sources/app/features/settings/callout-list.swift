import FolioDomain
import FolioMarkdown
import SwiftUI

struct CalloutList: View {
    @Bindable var model: SettingsModel
    @State private var defaultsOpen = false

    var body: some View {
        Block(String(localized: SettingItem.callouts.name)) {
            Card(clipped: true) {
                ForEach(model.customCallouts, id: \.name) { row($0) }
                DisclosureRow(label: String(localized: .settingsCalloutsDefaults), isOpen: $defaultsOpen) {
                    ForEach(model.defaultCallouts, id: \.name) { row($0) }
                }
                CardRow(last: true) {
                    TextField(String(localized: .settingsCalloutsNew), text: $model.newCallout)
                        .textFieldStyle(.plain)
                        .font(Theme.Typeface.mono)
                        .autocorrectionDisabled()
                        .onSubmit(model.addCallout)
                    Spacer(minLength: Theme.Space.s)
                    Button(.commonAdd, action: model.addCallout)
                        .buttonStyle(.ghost)
                        .disabled(!model.canAddCallout)
                }
            }
        }
    }

    func row(_ kind: CalloutKind) -> some View {
        CardRow {
            FoldingRow {
                HStack(spacing: Theme.Space.s) {
                    Circle().fill(NoteLook.tone(kind.tone).color).frame(width: Theme.Size.dot, height: Theme.Size.dot)
                    Text(kind.name).font(Theme.Typeface.mono).lineLimit(1)
                }
            } control: {
                FlowLayout(spacing: Theme.Space.tight, centered: true) {
                    ChoiceMenu(selection: field(kind, \.tone), options: CalloutKind.Tone.allCases.map { ($0, $0.label) })
                    ToggleChip(String(localized: .settingsCalloutsNumbered), isOn: field(kind, \.numbered))
                    ToggleChip(String(localized: .settingsCalloutsProvable), isOn: field(kind, \.provable))
                    if !kind.isDefault {
                        icon("minus.circle", help: .commonDelete) { model.removeCallout(kind.name) }
                    } else if model.changed(kind) {
                        icon("arrow.uturn.backward", help: .settingsCalloutsReset) { model.removeCallout(kind.name) }
                    }
                }
            }
        }
    }

    func icon(_ symbol: String, help: LocalizedStringResource, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).foregroundStyle(Theme.Palette.textTertiary)
                .frame(width: Theme.Size.toolbarButton, height: Theme.Size.toolbarButton).contentShape(TouchTarget())
        }
        .buttonStyle(.pointing(.plain))
        .help(Text(help))
        .accessibilityLabel(Text(help))
    }

    func field<T>(_ kind: CalloutKind, _ key: WritableKeyPath<CalloutKind, T>) -> Binding<T> {
        Binding(
            get: { kind[keyPath: key] },
            set: {
                var changed = kind
                changed[keyPath: key] = $0
                model.setCallout(changed)
            })
    }
}

extension CalloutKind.Tone {
    fileprivate var label: String {
        switch self {
        case .definition: String(localized: .settingsCalloutToneDefinition)
        case .theorem: String(localized: .settingsCalloutToneTheorem)
        case .example: String(localized: .settingsCalloutToneExample)
        case .warning: String(localized: .settingsCalloutToneWarning)
        case .danger: String(localized: .settingsCalloutToneDanger)
        case .neutral: String(localized: .settingsCalloutToneNeutral)
        }
    }
}
