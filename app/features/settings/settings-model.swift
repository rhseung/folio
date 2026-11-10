import FolioAI
import FolioDomain
import FolioStorage
import Foundation
import Observation

/// Edits go to a local copy and are saved to settings.json once typing pauses.
@MainActor @Observable
final class SettingsModel {
    let workspace: Workspace
    var settings = FolioDomain.Settings()
    /// Until the copy is filled from the workspace, saving would write defaults over the real file.
    private var loaded = false

    var apiKey = ""
    var keySaved = APIKeyStore.read() != nil
    var usage: [MonthlyUsage] = []
    /// The tab the window's link names. Starts at the one last chosen for a link that names none, though a window
    /// never holds one: `Workspace.entry(for:)` fills it in.
    private(set) var tab: SettingsTab

    init(workspace: Workspace, tab: SettingsTab = .general) {
        self.workspace = workspace
        self.tab = tab
    }

    func follow(_ link: AppLink) {
        guard link.kind == .settings, let page = link.settingsPage else { return }
        tab = SettingsTab(page)
    }

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

    /// From the Info.plist, not FolioVersion: only the build knows its build number (the commit count).
    var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return String(localized: .settingsVersionBuild(info["CFBundleShortVersionString"] as? String ?? "?", info["CFBundleVersion"] as? String ?? "?"))
    }

    var folderPath: String {
        workspace.gist.map { ($0.url.path as NSString).abbreviatingWithTildeInPath } ?? String(localized: .settingsNone)
    }

    // MARK: Class start

    enum RecordingTiming: Hashable { case onTime, before, after }

    /// The recording's offset as the row shows it: a direction, and minutes beside it.
    var recordingTiming: RecordingTiming {
        get {
            let offset = settings.classStart.recordingOffsetMinutes
            return offset == 0 ? .onTime : offset < 0 ? .before : .after
        }
        set {
            let current = abs(settings.classStart.recordingOffsetMinutes)
            let minutes = current == 0 ? Self.defaultLead : current
            settings.classStart.recordingOffsetMinutes = switch newValue {
            case .onTime: 0
            case .before: -minutes
            case .after: minutes
            }
        }
    }

    static let defaultLead = 5

    var recordingMinutes: Int {
        get { abs(settings.classStart.recordingOffsetMinutes) }
        set { settings.classStart.recordingOffsetMinutes = (recordingTiming == .before ? -1 : 1) * max(1, newValue) }
    }

    var classStartCourses: [LoadedCourse] { workspace.currentCourses }

    func follows(_ item: ClassStartSettings.Item, course: UUID) -> Bool { !settings.classStart.off(for: course).contains(item) }

    func setFollows(_ follows: Bool, _ item: ClassStartSettings.Item, course: UUID) {
        var off = settings.classStart.off(for: course)
        if follows { off.remove(item) } else { off.insert(item) }
        settings.classStart.setOff(off, for: course)
    }

    /// 기본 설정, 전체 제외, or the items off: 녹음 · 렉처 제외.
    func exceptionLabel(_ course: UUID) -> String {
        let off = ClassStartSettings.Item.allCases.filter(settings.classStart.off(for: course).contains)
        if off.isEmpty { return String(localized: .settingsClassStartFollows) }
        if off.count == ClassStartSettings.Item.allCases.count { return String(localized: .settingsClassStartAllOff) }
        return String(localized: .settingsClassStartSomeOff(off.map(\.label).joined(separator: " · ")))
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
        case .recording: String(localized: .settingsTabRecording)
        case .claude: "Claude"
        }
    }

    init(_ page: AppLink.SettingsPage) {
        self = switch page {
        case .profile: .profile
        case .general: .general
        case .notifications: .notifications
        case .backup: .backup
        case .letters: .catalog
        case .notes: .notes
        case .recording: .recording
        case .claude: .claude
        }
    }

    var page: AppLink.SettingsPage {
        switch self {
        case .profile: .profile
        case .general: .general
        case .notifications: .notifications
        case .backup: .backup
        case .catalog: .letters
        case .notes: .notes
        case .recording: .recording
        case .claude: .claude
        }
    }

    /// What a link without a tab (the sidebar, ⌘,) opens: the tab last picked.
    static var remembered: SettingsTab {
        UserDefaults.standard.string(forKey: storageKey).flatMap(SettingsTab.init(rawValue:)) ?? .general
    }
}

extension ClassStartSettings.Item {
    var label: String {
        switch self {
        case .recording: String(localized: .settingsClassStartRecording)
        case .roughNote: String(localized: .settingsClassStartRoughNote)
        case .lecture: String(localized: .settingsClassStartLecture)
        }
    }
}

extension ClassStartSettings.Place {
    var label: String {
        switch self {
        case .here: String(localized: .settingsClassStartPlaceHere)
        case .beside: String(localized: .settingsClassStartPlaceBeside)
        case .tab: String(localized: .settingsClassStartPlaceTab)
        case .window: String(localized: .settingsClassStartPlaceWindow)
        }
    }
}
