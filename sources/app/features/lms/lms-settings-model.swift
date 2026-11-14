import FolioDomain
import FolioLMS
import SwiftUI

@MainActor @Observable
final class LMSSettingsModel {
    let workspace: Workspace
    var connecting = false
    var confirmingDisconnect = false

    init(workspace: Workspace) { self.workspace = workspace }

    var lms: LMSConnection { workspace.lms }

    var syncDetail: String {
        switch lms.status {
        case .syncing: return String(localized: .lmsSyncing)
        case .needsLogin: return String(localized: .lmsNeedsLogin)
        case .failed(let reason): return reason
        case .off, .idle:
            let count = workspace.lmsInbox.proposals.count
            let last = workspace.lmsLastSync
            return count == 0 ? last : String(localized: .lmsSyncDetail(last, count))
        }
    }

    var warns: Bool {
        switch lms.status {
        case .needsLogin, .failed: true
        case .off, .idle, .syncing: false
        }
    }

    func sync() async { await workspace.syncLMS() }

    func disconnect() { lms.disconnect() }
}
