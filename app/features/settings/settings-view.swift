import FolioAI
import FolioDomain
import FolioStorage
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case profile = "내 정보", general = "일반", notifications = "알림", backup = "백업", catalog = "평어", notes = "노트", claude = "Claude"
    var id: Self { self }
    static let storageKey = "settingsTab"

    var symbol: String {
        switch self {
        case .profile: "person.crop.circle"
        case .general: "gearshape"
        case .notifications: "bell"
        case .backup: "externaldrive"
        case .catalog: "graduationcap"
        case .notes: "doc.text"
        case .claude: "sparkle"
        }
    }
}

extension EnvironmentValues {
    @Entry var showSettings: @MainActor (SettingsTab) -> Void = { _ in }
}

extension FocusedValues {
    /// The window's way to open settings, for the ⌘, menu item.
    @Entry var showSettings: (@MainActor (SettingsTab?) -> Void)?
}

struct SettingsView: View {
    @State private var model: SettingsModel
    @AppStorage(SettingsTab.storageKey) private var tab: SettingsTab = .general

    init(workspace: Workspace) { _model = State(initialValue: SettingsModel(workspace: workspace)) }

    var body: some View {
        // A column of sections beside the page, like a course's column, instead of a separate window with tabs.
        HStack(spacing: 0) {
            column.frame(width: Theme.Size.courseColumn)
            ColumnDivider()
            Page(maxWidth: 640) {
                PageHeader(title: tab.label)
                content(tab)
            }
            // Each section starts at its top, not at the scroll position of the one before.
            .id(tab)
        }
        .onAppear(perform: model.load)
        .onChange(of: model.workspace.settings) { _, new in model.reloaded(new) }
        .task(id: model.settings) { await model.saveAfterPause() }
        // Closing right after a change cancels the wait above; save what was left.
        .onDisappear(perform: model.saveNow)
    }

    var column: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                Text(.settingsTitle).font(Theme.Typeface.columnTitle).padding(.horizontal, Theme.Inset.listRow.leading)
                VStack(spacing: Theme.Space.xxs) {
                    ForEach(SettingsTab.allCases) { t in
                        let chosen = tab == t
                        Button { tab = t } label: { ColumnRow(title: t.label, symbol: t.symbol, chosen: chosen) }
                        .buttonStyle(.pointing(.plain))
                    }
                }
            }
            .padding(.horizontal, Theme.Inset.panel)
            .padding(.vertical, Theme.Space.l)
        }
        .font(Theme.Typeface.body)
        .foregroundStyle(Theme.Palette.text)
        .background(Theme.Palette.window)
    }

    @ViewBuilder func content(_ tab: SettingsTab) -> some View {
        switch tab {
        case .profile:
            // No block title: the page header already says 내 정보.
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                ProfileCard(workspace: model.workspace)
                Footnote(String(localized: .settingsProfileFootnote))
            }
        case .general: GeneralSettings(model: model)
        case .notifications: NotificationSettingsForm(settings: $model.settings.notifications)
        case .backup: BackupSettingsForm(model: model)
        case .catalog: CatalogEditor()
        case .notes: NoteSettingsForm(settings: $model.settings)
        case .claude: ClaudeSettings(model: model)
        }
    }
}

private struct GeneralSettings: View {
    @Bindable var model: SettingsModel
    @State private var pickingFolder = false
    @AppStorage(Appearance.storageKey) private var appearance: Appearance = .system

    var body: some View {
        Block(String(localized: .settingsScreen)) {
            Card {
                FormRow(label: String(localized: .settingsAppearance), detail: String(localized: .settingsAppearanceDetail), last: true) {
                    Segmented(selection: $appearance, options: Appearance.allCases.map { ($0, $0.label) }, symbols: Appearance.allCases.map(\.symbol))
                }
            }
        }
        Block(String(localized: .settingsGistFolder)) {
            Card {
                FormRow(label: String(localized: .settingsLocation), detail: model.folderPath, last: true) {
                    Button(.settingsPickFolder) { pickingFolder = true }
                }
            }
        }
        .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { model.workspace.open(url) }
        }
        Block(String(localized: .settingsDayAndReview)) {
            Card {
                FormRow(label: String(localized: .settingsDayBoundary), detail: String(localized: .settingsDayBoundaryDetail)) {
                    TimeMenu(minute: $model.settings.dayBoundaryMinutes, hours: 0...8)
                }
                FormRow(label: String(localized: .settingsDailyLimit), detail: String(localized: .settingsDailyLimitDetail)) {
                    let limit = model.settings.review.dailyLimit
                    ScrubField(value: Binding(get: { Double(limit ?? 10) }, set: { model.settings.review.dailyLimit = Int($0.rounded()) }),
                               range: 1...50, step: 1, width: 80)
                        .disabled(limit == nil)
                        .opacity(limit == nil ? 0.4 : 1)
                    Text(.settingsUnits).foregroundStyle(Theme.Palette.textSecondary)
                    Switch(isOn: Binding(get: { limit != nil }, set: { model.settings.review.dailyLimit = $0 ? 10 : nil }))
                }
                FormRow(label: String(localized: .settingsIntervals), detail: String(localized: .settingsIntervalsDetail), last: true) {
                    IntListField(values: $model.settings.review.intervals, unit: String(localized: .settingsUnitDays), range: 1...365)
                }
            }
        }
    }
}

private struct NotificationSettingsForm: View {
    @Binding var settings: NotificationSettings

    var body: some View {
        Block(String(localized: .settingsAssignments)) {
            Card {
                FormRow(label: String(localized: .settingsDueAlert), last: !settings.assignmentDue) { Switch(isOn: $settings.assignmentDue) }
                if settings.assignmentDue {
                    FormRow(label: String(localized: .settingsAlertLead), detail: String(localized: .settingsAlertLeadDetail), last: true) {
                        IntListField(values: $settings.assignmentLeadHours, unit: String(localized: .settingsUnitHoursBefore), range: 1...336)
                    }
                }
            }
        }
        Block(String(localized: .settingsExams)) {
            Card {
                FormRow(label: String(localized: .settingsDayBefore)) {
                    TimeMenu(minute: $settings.examDayBeforeMinute).disabled(!settings.examDayBefore).opacity(settings.examDayBefore ? 1 : 0.4)
                    Switch(isOn: $settings.examDayBefore)
                }
                FormRow(label: String(localized: .settingsMorningOf), last: true) {
                    TimeMenu(minute: $settings.examMorningMinute).disabled(!settings.examMorning).opacity(settings.examMorning ? 1 : 0.4)
                    Switch(isOn: $settings.examMorning)
                }
            }
        }
        Block(String(localized: .settingsReviewAndAttendance)) {
            Card {
                FormRow(label: String(localized: .settingsDailyReview), detail: String(localized: .settingsDailyReviewDetail)) {
                    TimeMenu(minute: $settings.dailyReviewMinute).disabled(!settings.dailyReview).opacity(settings.dailyReview ? 1 : 0.4)
                    Switch(isOn: $settings.dailyReview)
                }
                FormRow(label: String(localized: .settingsAttendanceAlert), last: true) { Switch(isOn: $settings.attendance) }
            }
            Footnote(String(localized: .settingsNotificationsFootnote))
        }
    }
}

private struct BackupSettingsForm: View {
    @Bindable var model: SettingsModel
    #if os(macOS)
    @State private var picking = false
    #endif

    var body: some View {
        #if os(macOS)
        Block(String(localized: .settingsAutoBackup)) {
            Card {
                FormRow(label: String(localized: .settingsDailyBackup), detail: String(localized: .settingsDailyBackupDetail(model.settings.backup.dailyDays))) {
                    Switch(isOn: $model.settings.backup.enabled)
                }
                FormRow(label: String(localized: .settingsLocation), detail: model.backupFolder) {
                    Button(.settingsChange) { picking = true }
                }
                FormRow(label: String(localized: .settingsLastBackup), detail: model.lastBackup, last: true) {
                    Button(model.backingUp ? .settingsBackingUp : .settingsBackUpNow) {
                        Task { await model.backUpNow() }
                    }
                    .disabled(model.backingUp)
                }
            }
            Footnote(String(localized: .settingsBackupFootnote))
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { model.pickBackupFolder(url) }
        }
        Block(String(localized: .settingsRestore), note: model.archives.count > SettingsModel.archiveLimit ? String(localized: .settingsRecentArchives(SettingsModel.archiveLimit)) : nil) {
            Card {
                if model.archives.isEmpty { CardRow(last: true) { EmptyLine(String(localized: .settingsNoBackups)) } }
                let shown = model.shownArchives
                ForEach(Array(shown.enumerated()), id: \.element.url) { i, archive in
                    CardRow(last: i == shown.count - 1) {
                        Text(archive.day.description).monospacedDigit()
                        Spacer()
                        SearchPicker(options: model.restoreOptions, pick: { restore($0, from: archive) }, prompt: String(localized: .settingsRestoreCoursePrompt)) {
                            ChipLabel(String(localized: .settingsRestoreCourse))
                        }
                    }
                }
            }
            Footnote(String(localized: .settingsRestoreFootnote))
        }
        .onAppear(perform: model.refreshArchives)
        .onChange(of: model.workspace.settings.backup) { _, _ in model.refreshArchives() }
        #else
        Block(String(localized: .settingsBackup)) {
            Card { CardRow(last: true) { EmptyLine(String(localized: .settingsBackupOnMac)) } }
        }
        #endif
    }

    #if os(macOS)
    func restore(_ course: UUID, from archive: BackupStore.Archive) {
        Task {
            if let folder = await model.restore(course, from: archive) {
                NSWorkspace.shared.activateFileViewerSelecting([folder])
            }
        }
    }
    #endif
}

private struct NoteSettingsForm: View {
    @Binding var settings: FolioDomain.Settings

    var body: some View {
        ForEach([NoteKind.review, .examSummary, .topic], id: \.self) { kind in
            Block(String(localized: .settingsTemplate(Self.name(kind))), note: kind == .review ? String(localized: .settingsTemplateNote) : nil) {
                // The raw list, blanks included, so a row just added stays until it's typed into.
                HeadingList(lines: Binding(
                    get: { settings.noteTemplates[kind.rawValue] ?? NoteTemplate.defaultSections(for: kind) },
                    set: { settings.noteTemplates[kind.rawValue] = $0 == NoteTemplate.defaultSections(for: kind) ? nil : $0 }
                ))
            }
        }
        Block(String(localized: .settingsMath), note: String(localized: .settingsMathNote)) {
            Card {
                FormRow(label: String(localized: .settingsMathSyntax), detail: String(localized: .settingsMathSyntaxDetail), last: true) {
                    ChoiceMenu(selection: $settings.newNoteMath, options: MathSyntax.allCases.map { ($0, $0.label) })
                }
            }
        }
        FormTextArea(label: String(localized: .settingsNoteRules), detail: String(localized: .settingsNoteRulesDetail), text: $settings.noteRules, height: 160)
    }

    static func name(_ kind: NoteKind) -> String {
        switch kind {
        case .review: String(localized: .settingsTemplateReview)
        case .examSummary: String(localized: .settingsTemplateExamSummary)
        case .topic: String(localized: .settingsTemplateTopic)
        default: ""
        }
    }
}

private struct ClaudeSettings: View {
    @Bindable var model: SettingsModel
    @AppStorage(Workspace.subscriptionKey) private var subscription = true

    var body: some View {
        Block(String(localized: .settingsConnection)) {
            Card {
                #if os(macOS)
                FormRow(label: String(localized: .settingsConnectionMethod), detail: model.connectionDetail(subscription: subscription)) {
                    ChoiceMenu(selection: $subscription, options: [(true, String(localized: .settingsSubscription)), (false, String(localized: .settingsApiKey))])
                }
                .onChange(of: subscription) { model.workspace.claudeRevision += 1 }
                #endif
                FormRow(label: String(localized: .settingsApiKey), detail: String(localized: .settingsApiKeyDetail), last: true) {
                    SecureField(model.keySaved ? String(localized: .settingsSaved) : "sk-ant-…", text: $model.apiKey).pill(width: 180).onSubmit(model.saveKey)
                    Button(.commonSave, action: model.saveKey).disabled(model.apiKey.isEmpty)
                }
            }
        }
        Block(String(localized: .settingsUsage), note: String(localized: .settingsUsageNote)) {
            Card {
                let shown = Array(model.usage.prefix(6))
                if shown.isEmpty { CardRow(last: true) { EmptyLine(String(localized: .settingsNoRequests)) } }
                ForEach(Array(shown.enumerated()), id: \.offset) { i, m in
                    CardRow(last: i == shown.count - 1) {
                        Text(SettingsModel.month(m)).monospacedDigit()
                        Spacer()
                        Text(.settingsRequestCount(m.requests)).monospacedDigit().foregroundStyle(Theme.Palette.textSecondary)
                        Text(m.cost, format: .currency(code: "USD")).monospacedDigit().frame(minWidth: 72, alignment: .trailing)
                    }
                }
            }
        }
        // Read once per visit: it parses every course's log file.
        .task(model.loadUsage)
    }
}

/// An explanation under a settings card, where a long block note would wrap beside its title.
struct Footnote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
            .padding(.horizontal, Theme.Space.l)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct Switch: View {
    @Binding var isOn: Bool
    var body: some View {
        Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch)
    }
}

/// Stored sorted, without repeats, and never empty.
struct IntListField: View {
    @Binding var values: [Int]
    let unit: String
    let range: ClosedRange<Int>
    @State private var adding = false
    @State private var draft = 1

    var body: some View {
        HStack(spacing: Theme.Space.tight) {
            ForEach(values, id: \.self) { v in
                HStack(spacing: Theme.Space.xs) {
                    Text("\(v)\(unit)").monospacedDigit()
                    if values.count > 1 {
                        Button { values.removeAll { $0 == v } } label: {
                            Image(systemName: "xmark").font(Theme.Glyph.tiny).foregroundStyle(Theme.Palette.textTertiary)
                        }
                        .buttonStyle(.pointing(.plain))
                        .help(Text(.commonRemove))
                    }
                }
                .chip()
                .fixedSize()
                .contextMenu {
                    // Never empty: the last value stays, as its × does.
                    Button(.commonRemove, role: .destructive) { values.removeAll { $0 == v } }.disabled(values.count < 2)
                }
            }
            Button {
                draft = min((values.last ?? 0) + 1, range.upperBound)
                adding = true
            } label: { Image(systemName: "plus") }
            .buttonStyle(.ghost)
            .help(Text(.commonAdd))
            .popover(isPresented: $adding) {
                HStack(spacing: Theme.Space.s) {
                    ScrubField(value: Binding(get: { Double(draft) }, set: { draft = min(max(Int($0.rounded()), range.lowerBound), range.upperBound) }),
                               range: Double(range.lowerBound)...Double(range.upperBound), step: 1, width: 88)
                    Text(unit).foregroundStyle(Theme.Palette.textSecondary)
                    Button(.commonAdd, action: add).buttonStyle(.pointing(.borderedProminent))
                }
                .padding(Theme.Space.m)
            }
        }
    }

    func add() {
        values = Array(Set(values + [draft])).sorted()
        adding = false
    }
}

struct HeadingList: View {
    @Binding var lines: [String]

    var body: some View {
        Card {
            ForEach(lines.indices, id: \.self) { i in
                CardRow {
                    Text("\(i + 1)").monospacedDigit().foregroundStyle(Theme.Palette.textTertiary).frame(width: 18, alignment: .trailing)
                    // Guarded: a removed row can still be asked for its text once while the list redraws.
                    TextField(String(localized: .settingsHeading), text: Binding(get: { lines.indices.contains(i) ? lines[i] : "" }, set: { if lines.indices.contains(i) { lines[i] = $0 } }))
                        .textFieldStyle(.plain)
                    Button { lines.remove(at: i) } label: {
                        Image(systemName: "minus.circle").foregroundStyle(Theme.Palette.textTertiary)
                    }
                    .buttonStyle(.pointing(.plain))
                    .help(Text(.commonDelete))
                }
                .contextMenu { Button(.commonDelete, role: .destructive) { if lines.indices.contains(i) { lines.remove(at: i) } } }
            }
            CardRow(last: true) {
                Button { lines.append("") } label: {
                    Label(.settingsAddHeading, systemImage: "plus").foregroundStyle(Theme.Palette.textSecondary)
                }
                .buttonStyle(.pointing(.plain))
            }
        }
    }
}
