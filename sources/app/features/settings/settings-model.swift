import FolioAI
import FolioDomain
import FolioStorage
import Foundation
import Observation

@MainActor @Observable
final class SettingsModel {
    let workspace: Workspace
    var settings = FolioDomain.Settings()
    // 사본을 workspace에서 채우기 전에 저장하면 기본값이 실제 파일을 덮어쓴다.
    private var loaded = false

    var apiKey = ""
    var keyHint = SettingsModel.hint(of: APIKeyStore.read())
    var replacingKey = false
    var usage: [MonthlyUsage] = []
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

    // 다른 기기의 저장이 오면 그 값에서 다시 시작한다. 그러지 않으면 다음 저장이 그 변경을 되돌린다.
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

    // 빌드 번호(커밋 수)는 빌드만 알므로 FolioVersion이 아니라 Info.plist에서 읽는다.
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

    var referenceClass: StartingClass? {
        let courses = workspace.currentCourses.map { ClassStart.Course(file: $0.file, term: workspace.semester(of: $0.file.course)) }
        return ClassStart.next(courses, settings: settings, now: workspace.liveNow, calendar: workspace.calendar)
    }

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

    func exceptionLabel(_ course: UUID) -> String {
        let off = ClassStartSettings.Item.allCases.filter(settings.classStart.off(for: course).contains)
        if off.isEmpty { return String(localized: .settingsClassStartFollows) }
        if off.count == ClassStartSettings.Item.allCases.count { return String(localized: .settingsClassStartAllOff) }
        return String(localized: .settingsClassStartSomeOff(off.map(\.label).joined(separator: " · ")))
    }

    // MARK: Pane layouts

    var classStartPresets: [PanePreset] { settings.presets.filter(\.opensClass) }

    var classStartPreset: String {
        get { settings.classStartPreset.id }
        set { settings.classStart.preset = newValue == PanePreset.inClass.id ? nil : newValue }
    }

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

    func delete(_ id: String) {
        settings.panePresets.removeAll { $0.id == id }
        if settings.classStart.preset == id { settings.classStart.preset = nil }
    }

    // MARK: Review

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

    // GIST 폴더 안의 백업은 자기 자신 안에 백업되고 모든 기기로 동기화된다.
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

    #if os(macOS)
    func connectionDetail(subscription: Bool) -> String? {
        guard subscription else { return nil }
        return CLIProvider.find()?.path ?? String(localized: .settingsClaudeCliMissing)
    }

    func connectionWarns(subscription: Bool) -> Bool { subscription && CLIProvider.find() == nil }
    #endif

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
        case .lms: "LMS"
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
            case .lms: .lms
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
        case .lms: .lms
        case .backup: .backup
        case .about: .about
        }
    }

    // 예전에는 탭을 한국어 이름으로 저장했으므로, 그때 고른 탭도 그 탭이나 그것을 넘겨받은 탭으로 연다.
    static let formerNames: [String: SettingsTab] = [  // strings: data, read back from settings
        "내 정보": .record, "평어": .record, "녹음": .classes, "일반": .general, "알림": .notifications, "백업": .backup,
        "노트": .notes, "Claude": .claude, "앱 정보": .about,
    ]

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
