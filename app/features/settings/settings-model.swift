import FolioAI
import FolioCore
import FolioDomain
import FolioMarkdown
import FolioStorage
import Foundation
import Observation

@MainActor @Observable
final class SettingsModel {
    let workspace: Workspace
    var settings = FolioDomain.Settings() { didSet { json = settings.json } }
    // 선언으로 그린 행이 값을 읽을 때마다 설정 전체를 다시 인코딩하지 않도록 한 번만 만든다.
    private(set) var json = FolioDomain.Settings().json
    // 사본을 workspace에서 채우기 전에 저장하면 기본값이 실제 파일을 덮어쓴다.
    private var loaded = false

    var apiKey = ""
    var keyHint = SettingsModel.hint(of: APIKeyStore.read())
    var replacingKey = false
    var usage: [MonthlyUsage] = []
    private(set) var tab: AppLink.SettingsPage

    init(workspace: Workspace, tab: AppLink.SettingsPage = .general) {
        self.workspace = workspace
        self.tab = tab
    }

    func follow(_ link: AppLink) {
        guard link.kind == .settings, let page = link.settingsPage else { return }
        tab = page
    }

    func load() {
        settings = workspace.settings
        loaded = true
    }

    // 다른 기기의 저장이 오면 그 값에서 다시 시작한다. 그러지 않으면 다음 저장이 그 변경을 되돌린다.
    func reloaded(_ new: FolioDomain.Settings) { settings = new }

    func saveAfterPause() async {
        guard loaded else { return }
        try? await Task.sleep(for: SavePause.delay)
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

    // MARK: Declared rows

    func value(_ item: SettingItem) -> JSONValue { item.current(in: json) }

    func set(_ item: SettingItem, _ value: JSONValue) {
        // 컨트롤이 같은 값을 다시 써도 `settings`를 바꾸면 화면이 다시 그려지고 저장이 예약되므로, 바뀐 값만 넣는다.
        if let new = item.writing(value, into: settings), new != settings { settings = new }
    }

    func text(of item: SettingItem) -> String {
        if case .string(let s) = value(item) { s } else { "" }
    }

    func detail(of item: SettingItem) -> String? {
        item.key == SettingItem.reviewIntervals.key ? reviewDays : nil
    }

    // MARK: Class start

    var classStartItems: Set<ClassStartSettings.Item> {
        get { Set(ClassStartSettings.Item.allCases.filter { isOn($0) }) }
        set { for item in ClassStartSettings.Item.allCases { setOn(newValue.contains(item), item) } }
    }

    @ObservationIgnored private var keptRecording = ClassStartSettings.Recording.start
    @ObservationIgnored private var keptRoughNote = ClassStartSettings.RoughNote.create

    func isOn(_ item: ClassStartSettings.Item) -> Bool { settings.classStart.isOn(item) }

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

    // MARK: Callouts

    var newCallout = ""

    var callouts: CalloutTable { CalloutTable(settings) }
    var customCallouts: [CalloutKind] { callouts.kinds.filter { !$0.isDefault } }
    var defaultCallouts: [CalloutKind] { callouts.kinds.filter(\.isDefault) }

    func changed(_ kind: CalloutKind) -> Bool { kind.isDefault && settings.callouts?.contains { $0.name == kind.name } == true }

    // 기본 종류와 같아진 종류는 설정에서 빼서, 기본 종류가 앱과 함께 바뀌면 따라가게 한다.
    func setCallout(_ kind: CalloutKind) {
        var list = settings.callouts ?? []
        let stored = NoteCallout(name: kind.name, tone: kind.tone.rawValue, numbered: kind.numbered, provable: kind.provable)
        let same = CalloutKind.defaults.contains { $0 == kind }
        if let i = list.firstIndex(where: { $0.name == kind.name }) {
            if same { list.remove(at: i) } else { list[i] = stored }
        } else if !same {
            list.append(stored)
        }
        settings.callouts = list.isEmpty ? nil : list
    }

    func removeCallout(_ name: String) {
        let list = (settings.callouts ?? []).filter { $0.name != name }
        settings.callouts = list.isEmpty ? nil : list
    }

    var newCalloutName: String { newCallout.trimmingCharacters(in: .whitespaces).lowercased() }
    var canAddCallout: Bool { CalloutKind.allows(newCalloutName) && callouts[newCalloutName] == nil }

    func addCallout() {
        guard canAddCallout else { return }
        setCallout(CalloutKind(newCalloutName, .neutral))
        newCallout = ""
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

    var restoreOptions: [SelectOption<UUID>] {
        workspace.semesters.flatMap { s in workspace.courses(in: s).map { SelectOption(id: $0.id, label: $0.title, section: s.title) } }
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
