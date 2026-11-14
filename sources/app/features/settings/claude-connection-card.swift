import FolioAI
import FolioDomain
import FolioStorage
import SwiftUI

struct ClaudeConnectionCard: View {
    @Bindable var model: SettingsModel
    @AppStorage(Workspace.subscriptionKey) private var subscription = true

    var body: some View {
        Card {
            #if os(macOS)
            FormRow(
                label: String(localized: .settingsConnectionMethod), detail: model.connectionDetail(subscription: subscription),
                device: true, warns: model.connectionWarns(subscription: subscription)
            ) {
                ChoiceMenu(
                    selection: $subscription,
                    options: [(true, String(localized: .settingsSubscription)), (false, String(localized: .settingsApiKey))])
            }
            .onChange(of: subscription) { model.workspace.claudeRevision += 1 }
            #endif
            if let hint = model.keyHint, !model.replacingKey {
                FormRow(label: String(localized: .settingsApiKey), last: true) {
                    Text(hint).font(Theme.Typeface.mono).foregroundStyle(Theme.Palette.textSecondary)
                    Button(.settingsChange) { model.replacingKey = true }
                }
            } else {
                FormRow(
                    label: String(localized: .settingsApiKey),
                    detail: model.keyMissing(subscription: subscription) ? String(localized: .settingsApiKeyMissing) : nil, warns: true,
                    last: true
                ) {
                    SecureField("sk-ant-…", text: $model.apiKey).pill(width: 180).onSubmit(model.saveKey)  // strings: data, the key's form
                    Button(.commonSave, action: model.saveKey).disabled(model.apiKey.isEmpty)
                }
            }
        }
    }
}
