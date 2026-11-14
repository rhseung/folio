import FolioDomain
import FolioLMS
import SwiftUI

struct LMSSettingsForm: View {
    @State private var model: LMSSettingsModel

    init(workspace: Workspace) { _model = State(initialValue: LMSSettingsModel(workspace: workspace)) }

    var body: some View {
        Block(String(localized: .lmsConnection)) {
            Card {
                if let username = model.lms.username {
                    FormRow(label: String(localized: .lmsStudentNumber)) {
                        Text(username).monospacedDigit().foregroundStyle(Theme.Palette.textSecondary).textSelection(.enabled)
                    }
                    FormRow(label: String(localized: .lmsLastSyncLabel), detail: model.syncDetail, warns: model.warns) {
                        if model.lms.status == .needsLogin {
                            Button(.lmsReconnect) { model.connecting = true }.buttonStyle(.prominent)
                        } else {
                            Button {
                                Task { await model.sync() }
                            } label: {
                                Label(.lmsSyncNow, systemImage: "arrow.clockwise")
                            }
                            .disabled(model.lms.status == .syncing)
                        }
                    }
                    FormRow(label: String(localized: .lmsLogin), detail: String(localized: .lmsKeychain), last: true) {
                        Button(.lmsDisconnectEllipsis) { model.confirmingDisconnect = true }
                    }
                } else {
                    FormRow(label: String(localized: .lmsAccount), detail: String(localized: .lmsNotConnected), last: true) {
                        Button {
                            model.connecting = true
                        } label: {
                            Label(.lmsConnectButton, systemImage: "link")
                        }.buttonStyle(.prominent)
                    }
                }
            }
        }
        .task {
            if model.lms.isConnected, model.lms.snapshot == nil { await model.sync() }
        }
        .sheet(isPresented: $model.connecting) {
            LMSConnectSheet(lms: model.lms, username: model.lms.username ?? "") { Task { await model.sync() } }
        }
        .confirmationDialog(String(localized: .lmsDisconnectTitle), isPresented: $model.confirmingDisconnect) {
            Button(.lmsDisconnect, role: .destructive) { model.disconnect() }
        } message: {
            Text(.lmsDisconnectMessage)
        }
    }
}

private struct LMSConnectSheet: View {
    let lms: LMSConnection
    @State var username: String
    let connected: () -> Void
    @State private var password = ""
    @State private var trying = false
    @State private var failure: String?
    @Environment(\.dismiss) private var dismiss

    init(lms: LMSConnection, username: String, connected: @escaping () -> Void) {
        self.lms = lms
        _username = State(initialValue: username)
        self.connected = connected
    }

    var body: some View {
        SheetForm(
            title: String(localized: .lmsConnectTitle), confirm: String(localized: .lmsConnect),
            disabled: trying || username.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty,
            note: failure ?? String(localized: .lmsConnectNote)
        ) {
            FormRow(label: String(localized: .lmsStudentNumber)) {
                TextField(String(localized: .lmsStudentNumber), text: $username).pill(width: 220).textContentType(.username)
            }
            FormRow(label: String(localized: .lmsPassword), last: true) {
                SecureField(String(localized: .lmsPassword), text: $password).pill(width: 220).textContentType(.password)
            }
        } onConfirm: {
            Task {
                trying = true
                defer { trying = false }
                do {
                    try await lms.connect(username: username, password: password)
                    dismiss()
                    connected()
                } catch {
                    failure =
                        LMSConnection.status(after: error) == .needsLogin ? String(localized: .lmsLoginRefused) : error.localizedDescription
                }
            }
        }
    }
}
