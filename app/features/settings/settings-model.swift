import FolioAI
import FolioDomain
import FolioStorage
import Foundation
import Observation

/// docs/SPEC.md "설정". Edits go to a local copy and are saved to settings.json once typing pauses.
@MainActor @Observable
final class SettingsModel {
    let workspace: Workspace
    var settings = FolioDomain.Settings()
    /// Until the copy is filled from the workspace, saving would write defaults over the real file.
    private var loaded = false

    var apiKey = ""
    var keySaved = APIKeyStore.read() != nil
    var usage: [MonthlyUsage] = []

    init(workspace: Workspace) { self.workspace = workspace }

    func load() {
        settings = workspace.settings
        loaded = true
    }

    /// Another device's save arrived: start from it, or the next save would undo it.
    func reloaded(_ new: FolioDomain.Settings) { settings = new }

    func saveAfterPause() async {
        guard loaded else { return }
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled else { return }
        saveNow()
    }

    func saveNow() {
        if loaded, settings != workspace.settings { workspace.saveSettings(settings) }
    }

    var folderPath: String {
        workspace.gist.map { ($0.url.path as NSString).abbreviatingWithTildeInPath } ?? String(localized: .settingsNone)
    }

    // MARK: Backup

    #if os(macOS)
    static let archiveLimit = 12

    var archives: [BackupStore.Archive] = []
    var backingUp = false

    var shownArchives: [BackupStore.Archive] { Array(archives.prefix(Self.archiveLimit)) }

    var lastBackup: String { archives.first.map { "\($0.day)" } ?? String(localized: .settingsNone) }

    var backupFolder: String { (settings.backup.folder as NSString).abbreviatingWithTildeInPath }

    var restoreOptions: [PickOption<UUID>] {
        workspace.semesters.flatMap { s in workspace.courses(in: s).map { PickOption(id: $0.id, title: $0.title, section: s.title) } }
    }

    func refreshArchives() { archives = workspace.backupStore?.archives() ?? [] }

    func backUpNow() async {
        backingUp = true
        await workspace.backUpNow()
        backingUp = false
        refreshArchives()
    }

    /// A backup inside the GIST folder would be backed up into itself and synced to every device.
    func pickBackupFolder(_ url: URL) {
        if let gist = workspace.gist, (url.standardizedFileURL.path + "/").hasPrefix(gist.url.standardizedFileURL.path + "/") {
            workspace.error = String(localized: .settingsBackupInsideGist)
        } else {
            settings.backup.folder = url.path
        }
    }

    func restore(_ course: UUID, from archive: BackupStore.Archive) async -> URL? {
        await workspace.restore(course, from: archive)
    }
    #endif

    // MARK: Claude

    #if os(macOS)
    func connectionDetail(subscription: Bool) -> String {
        guard subscription else { return String(localized: .settingsClaudeApiDetail) }
        return CLIProvider.find().map { String(localized: .settingsClaudeCliFound($0.path)) } ?? String(localized: .settingsClaudeCliMissing)
    }
    #endif

    func loadUsage() { usage = workspace.monthlyAPIUsage() }

    func saveKey() {
        guard !apiKey.isEmpty else { return }
        workspace.perform {
            // folio:not-an-action the API key goes to the keychain
            try APIKeyStore.save(self.apiKey)
            self.apiKey = ""
            self.keySaved = true
            self.workspace.claudeRevision += 1
        }
    }

    static func month(_ m: MonthlyUsage) -> String { String(localized: .settingsUsageMonth(String(m.year), m.month)) }
}

extension SettingsTab {
    var label: String {
        switch self {
        case .profile: String(localized: .settingsTabProfile)
        case .general: String(localized: .settingsTabGeneral)
        case .notifications: String(localized: .settingsTabNotifications)
        case .backup: String(localized: .settingsTabBackup)
        case .catalog: String(localized: .settingsTabCatalog)
        case .notes: String(localized: .settingsTabNotes)
        case .claude: "Claude"
        }
    }
}
