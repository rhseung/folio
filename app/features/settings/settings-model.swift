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
    /// The saved key's last characters, so the row can say which key is saved without showing it.
    var keyHint = SettingsModel.hint(of: APIKeyStore.read())
    var replacingKey = false
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
        return String(
            localized: .settingsVersionBuild(
                info["CFBundleShortVersionString"] as? String ?? "?", info["CFBundleVersion"] as? String ?? "?"))
    }

    var folderPath: String {
        workspace.gist.map { ($0.url.path as NSString).abbreviatingWithTildeInPath } ?? String(localized: .settingsNone)
    }

    // MARK: Class start

    /// What a class starts, as the chips show it. A chip turned off keeps its item's way (확인 후 시작, 열지 않음)
    /// for when it comes back on.
    var classStartItems: Set<ClassStartSettings.Item> {
        get { Set(ClassStartSettings.Item.allCases.filter { isOn($0) }) }
        set { for item in ClassStartSettings.Item.allCases { setOn(newValue.contains(item), item) } }
    }

    @ObservationIgnored private var keptRecording = ClassStartSettings.Recording.start
    @ObservationIgnored private var keptRoughNote = ClassStartSettings.RoughNote.create

    func isOn(_ item: ClassStartSettings.Item) -> Bool {
        switch item {
        case .recording: settings.classStart.recording != .off
        case .roughNote: settings.classStart.roughNote != .off
        case .lecture: settings.classStart.lecture != .off
        }
    }

    func setOn(_ on: Bool, _ item: ClassStartSettings.Item) {
        guard on != isOn(item) else { return }
        switch item {
        case .recording:
            if !on { keptRecording = settings.classStart.recording }
            settings.classStart.recording = on ? keptRecording : .off
        case .roughNote:
            if !on { keptRoughNote = settings.classStart.roughNote }
            settings.classStart.roughNote = on ? keptRoughNote : .off
        case .lecture:
            settings.classStart.lecture = on ? .open : .off
        }
    }

    var startsSomething: Bool { !classStartItems.isEmpty }
    var opensPages: Bool { isOn(.roughNote) || isOn(.lecture) }

    /// The class the recording span's real times are for: the one under way, or else the next.
    var referenceClass: StartingClass? {
        let courses = workspace.currentCourses.map { ClassStart.Course(file: $0.file, term: workspace.semester(of: $0.file.course)) }
        return ClassStart.next(courses, settings: settings, now: workspace.liveNow, calendar: workspace.calendar)
    }

    /// `9:55 – 11:20`, or `9:55 – 직접 정지`: what the minutes before and after come to for a real class.
    var recordingSpanTimes: String? {
        guard let c = referenceClass else { return nil }
        let start = ClassStart.recordingStart(c, settings: settings.classStart)
        let stop = ClassStart.recordingStop(c, settings: settings.classStart)
        return String(
            localized: .settingsClassStartSpanTimes(
                Self.clock(start), stop.map(Self.clock) ?? String(localized: .settingsClassStartManualStop)))
    }

    var referenceTitle: String {
        referenceClass.flatMap { c in workspace.currentCourses.first { $0.id == c.courseId }?.title }
            ?? String(localized: .settingsPreviewClass)
    }

    static func clock(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }

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

    // MARK: Pane layouts

    /// The layouts a class's start can open its pages in: those with its lecture or note.
    var classStartPresets: [PanePreset] { settings.presets.filter(\.opensClass) }

    var classStartPreset: String {
        get { settings.classStartPreset.id }
        set { settings.classStart.preset = newValue == PanePreset.inClass.id ? nil : newValue }
    }

    /// `노트 · 05_Matchings.pdf`: what each pane holds, a role by its kind and an address by what it opens.
    func summary(of preset: PanePreset) -> String {
        preset.slots.map { slot in
            switch slot {
            case .role(let role): role.label
            case .link(let link): workspace.name(of: link) ?? link.string
            }
        }
        .joined(separator: " · ")
    }

    func rename(_ id: String, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let i = settings.panePresets.firstIndex(where: { $0.id == id }) else { return }
        settings.panePresets[i].name = name
    }

    func canMove(_ id: String, by offset: Int) -> Bool {
        settings.panePresets.firstIndex { $0.id == id }.map { settings.panePresets.indices.contains($0 + offset) } ?? false
    }

    func move(_ id: String, by offset: Int) {
        guard canMove(id, by: offset), let i = settings.panePresets.firstIndex(where: { $0.id == id }) else { return }
        settings.panePresets.swapAt(i, i + offset)
    }

    /// A class whose start opened the deleted layout goes back to "수업 중".
    func delete(_ id: String) {
        settings.panePresets.removeAll { $0.id == id }
        if settings.classStart.preset == id { settings.classStart.preset = nil }
    }

    // MARK: Review

    /// `11/10 → 11/11 · 11/14 · 11/21`: the days a unit studied today comes back.
    var reviewDays: String {
        let today = workspace.today
        let days = settings.review.reviewDays(after: today).map(Self.monthDay).joined(separator: " · ")
        return String(localized: .settingsIntervalsDays(Self.monthDay(today), days))
    }

    static func monthDay(_ day: LocalDate) -> String { "\(day.month)/\(day.day)" }

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

    var keySaved: Bool { keyHint != nil }

    /// Where Claude Code was found; nothing to say for the API key, whose row says it.
    #if os(macOS)
    func connectionDetail(subscription: Bool) -> String? {
        guard subscription else { return nil }
        return CLIProvider.find()?.path ?? String(localized: .settingsClaudeCliMissing)
    }

    func connectionWarns(subscription: Bool) -> Bool { subscription && CLIProvider.find() == nil }
    #endif

    /// Only where the key is what Claude goes through: on Mac with Claude Code it isn't needed.
    func keyMissing(subscription: Bool) -> Bool {
        #if os(macOS)
        !keySaved && !subscription
        #else
        !keySaved
        #endif
    }

    func loadUsage() { usage = workspace.monthlyAPIUsage() }

    func saveKey() {
        guard !apiKey.isEmpty else { return }
        workspace.perform {
            // folio:not-an-action the API key goes to the keychain
            try APIKeyStore.save(self.apiKey)
            self.keyHint = Self.hint(of: self.apiKey)
            self.apiKey = ""
            self.replacingKey = false
            self.workspace.claudeRevision += 1
        }
    }

    /// `sk-ant-…7Qx2`: the prefix every key shares and the key's last four.
    static func hint(of key: String?) -> String? {
        guard let key, !key.isEmpty else { return nil }
        return "sk-ant-…" + key.suffix(4)
    }

    static func month(_ m: MonthlyUsage) -> String { String(localized: .settingsUsageMonth(String(m.year), m.month)) }
}

extension SettingsTab {
    var label: String {
        switch self {
        case .general: String(localized: .settingsTabGeneral)
        case .record: String(localized: .settingsTabRecord)
        case .classes: String(localized: .settingsTabClass)
        case .notes: String(localized: .settingsTabNotes)
        case .review: String(localized: .settingsTabReview)
        case .notifications: String(localized: .settingsTabNotifications)
        case .claude: "Claude"
        case .backup: String(localized: .settingsTabBackup)
        case .about: String(localized: .settingsTabAbout)
        }
    }

    init(_ page: AppLink.SettingsPage) {
        self =
            switch page {
            case .general: .general
            case .record: .record
            case .classes: .classes
            case .notes: .notes
            case .review: .review
            case .notifications: .notifications
            case .claude: .claude
            case .backup: .backup
            case .about: .about
            }
    }

    var page: AppLink.SettingsPage {
        switch self {
        case .general: .general
        case .record: .record
        case .classes: .classes
        case .notes: .notes
        case .review: .review
        case .notifications: .notifications
        case .claude: .claude
        case .backup: .backup
        case .about: .about
        }
    }

    /// Tabs were stored by their Korean names before #416; a tab picked then still opens, or the one that took it over.
    static let formerNames: [String: SettingsTab] = [  // strings: data, read back from settings
        "내 정보": .record, "평어": .record, "녹음": .classes, "일반": .general, "알림": .notifications, "백업": .backup,
        "노트": .notes, "Claude": .claude, "앱 정보": .about,
    ]

    /// What a link without a tab (the sidebar, ⌘,) opens: the tab last picked.
    static var remembered: SettingsTab {
        guard let stored = UserDefaults.standard.string(forKey: storageKey) else { return .general }
        return SettingsTab(rawValue: stored) ?? formerNames[stored] ?? .general
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

    var symbol: String {
        switch self {
        case .recording: "waveform"
        case .roughNote: "doc.text"
        case .lecture: "rectangle.on.rectangle"
        }
    }
}
