import FolioAI
import FolioDomain
import FolioStorage
import SwiftUI

extension EnvironmentValues {
    @Entry var showSettings: @MainActor (SettingsTab) -> Void = { _ in }
}

extension FocusedValues {
    @Entry var showSettings: (@MainActor (SettingsTab?) -> Void)?
}

struct SettingsView: View {
    @State private var model: SettingsModel
    @AppStorage(SettingsTab.storageKey) private var remembered: SettingsTab = .general
    @Environment(\.place) private var place
    @Environment(\.openLink) private var openLink

    init(workspace: Workspace) { _model = State(initialValue: SettingsModel(workspace: workspace, tab: .remembered)) }

    var tab: SettingsTab { model.tab }

    // 고를 때만 기억해야, 링크나 뒤로 가기로 탭에 와도 사이드바가 다음에 여는 탭이 바뀌지 않는다.
    func pick(_ t: SettingsTab) {
        remembered = t
        openLink(.settings(t.page))
    }

    var body: some View {
        ColumnSplit(kind: .settingsTabs) {
            SettingsColumn(tab: tab, pick: pick)
        } content: {
            Page(maxWidth: 640) {
                PageHeader(title: tab.label)
                content(tab)
            }
            .id(tab)
        }
        .onChange(of: place, initial: true) { _, entry in if let entry { model.follow(entry.link) } }
        .onAppear(perform: model.load)
        .onChange(of: model.workspace.settings) { _, new in model.reloaded(new) }
        .task(id: model.settings) { await model.saveAfterPause() }
        // 변경 직후에 닫으면 위의 대기가 취소되므로 남은 것을 저장한다.
        .onDisappear(perform: model.saveNow)
    }

    @ViewBuilder func content(_ tab: SettingsTab) -> some View {
        switch tab {
        case .general: GeneralSettings(model: model)
        case .record:
            Block(String(localized: .settingsProfile)) { ProfileCard(workspace: model.workspace) }
            Block(String(localized: .settingsLetters)) { CatalogEditor() }
        case .classes: ClassSettings(model: model)
        case .notes: NoteSettingsForm(model: model)
        case .review: ReviewSettingsForm(model: model)
        case .notifications: NotificationSettingsForm(settings: $model.settings.notifications)
        case .claude: ClaudeSettings(model: model)
        case .lms: LMSSettingsForm(workspace: model.workspace)
        case .backup: BackupSettingsForm(model: model)
        case .about: AboutSettings(model: model)
        }
    }
}

// 그 자리에서 준 `closeColumn`을 페이지 위에 연 열이 읽도록 따로 뷰로 둔다.
private struct SettingsColumn: View {
    let tab: SettingsTab
    let pick: (SettingsTab) -> Void
    @Environment(\.closeColumn) private var closeColumn

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                Text(.settingsTitle).font(Theme.Typeface.columnTitle).padding(.horizontal, Theme.Inset.listRow.leading)
                VStack(spacing: Theme.Space.m) {
                    ForEach(0..<3, id: \.self) { run in
                        VStack(spacing: Theme.Space.xxs) {
                            ForEach(SettingsTab.allCases.filter { $0.run == run }) { t in
                                Button {
                                    pick(t)
                                    closeColumn()
                                } label: {
                                    ColumnRow(title: t.label, symbol: t.symbol, chosen: tab == t)
                                }
                                .buttonStyle(.pointing(.plain))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Inset.panel)
            .padding(.vertical, Theme.Space.l)
            .clearOfColumnButtons(inset: Theme.Space.l)
        }
        .overflowFade(.vertical)
        .font(Theme.Typeface.body)
        .foregroundStyle(Theme.Palette.text)
        .columnBackground()
    }
}

private struct GeneralSettings: View {
    @Bindable var model: SettingsModel
    @State private var pickingFolder = false
    @AppStorage(Appearance.storageKey) private var appearance: Appearance = .system

    var body: some View {
        Block(String(localized: .settingsScreenAndFolder)) {
            Card {
                FormRow(label: String(localized: .settingsAppearance), device: true) {
                    Segmented(
                        selection: $appearance, options: Appearance.allCases.map { ($0, $0.label) },
                        symbols: Appearance.allCases.map(\.symbol))
                }
                FormRow(label: String(localized: .settingsGistFolder), detail: model.folderPath, device: true) {
                    Button(.settingsPickFolder) { pickingFolder = true }
                }
                FormRow(label: String(localized: .settingsFirstRun), last: true) {
                    Button(.settingsFirstRunShow) { model.workspace.showsFirstRun = true }
                }
            }
        }
        .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { model.workspace.open(url) }
        }
        Block(String(localized: .settingsDay)) {
            Card {
                FormRow(label: String(localized: .settingsDayBoundary), last: true) {
                    TimeMenu(minute: $model.settings.dayBoundaryMinutes, hours: 0...8)
                }
            }
        }
        PaneLayoutSettings(model: model)
    }
}

private struct PaneLayoutSettings: View {
    @Bindable var model: SettingsModel
    @State private var renaming: PanePreset?
    @State private var name = ""

    var body: some View {
        Block(String(localized: .settingsPaneLayouts)) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Card {
                    FormRow(label: String(localized: .settingsClassStartLayout), last: true) {
                        ChoiceMenu(selection: $model.classStartPreset, options: model.classStartPresets.map { ($0.id, $0.title) })
                    }
                }
                Card {
                    let all = model.settings.presets
                    ForEach(all) { preset in
                        row(preset, last: preset.id == all.last?.id)
                    }
                }
                if model.settings.panePresets.isEmpty {
                    Text(.settingsPaneLayoutsEmpty).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary)
                        .padding(.horizontal, Theme.Space.l)
                }
            }
        }
        .alert(
            String(localized: .panesPresetsRenameTitle), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
        ) {
            TextField(String(localized: .panesPresetsNameField), text: $name)
            Button(String(localized: .commonSave)) {
                if let renaming { model.rename(renaming.id, to: name) }
                renaming = nil
            }
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button(String(localized: .commonCancel), role: .cancel) { renaming = nil }
        }
    }

    func row(_ preset: PanePreset, last: Bool) -> some View {
        CardRow(last: last) {
            LayoutGlyph(shares: preset.shares)
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                HStack(spacing: Theme.Space.s) {
                    Text(preset.title).lineLimit(1)
                    if preset.isBuiltIn { Chip(String(localized: .settingsPaneLayoutsBuiltIn)) }
                }
                Text(model.summary(of: preset)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: Theme.Space.s)
            if !preset.isBuiltIn { menu(preset) }
        }
    }

    func menu(_ preset: PanePreset) -> some View {
        Menu {
            Button(String(localized: .settingsPaneLayoutsRename)) {
                name = preset.title
                renaming = preset
            }
            Button(String(localized: .settingsPaneLayoutsMoveUp)) { model.move(preset.id, by: -1) }
                .disabled(!model.canMove(preset.id, by: -1))
            Button(String(localized: .settingsPaneLayoutsMoveDown)) { model.move(preset.id, by: 1) }
                .disabled(!model.canMove(preset.id, by: 1))
            Divider()
            Button(String(localized: .settingsPaneLayoutsDelete), role: .destructive) { model.delete(preset.id) }
        } label: {
            Image(systemName: "ellipsis").foregroundStyle(Theme.Palette.textSecondary)
                .frame(width: Theme.Size.toolbarButton, height: Theme.Size.toolbarButton).contentShape(TouchTarget())
        }
        .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.borderless).pointingHand().fixedSize()
        .help(Text(.settingsPaneLayoutsMore))
        .accessibilityLabel(Text(.settingsPaneLayoutsMore))
    }
}

private struct LayoutGlyph: View {
    let shares: [Double]

    var body: some View {
        GeometryReader { proxy in
            let gap = Theme.Space.xxs
            let room = proxy.size.width - gap * CGFloat(max(0, shares.count - 1))
            HStack(spacing: gap) {
                ForEach(shares.indices, id: \.self) { i in
                    let shape = RoundedRectangle(cornerRadius: Theme.Radius.mark)
                    shape.fill(Theme.Palette.text.opacity(Theme.Opacity.tint))
                        .overlay { shape.strokeBorder(Theme.Palette.text.opacity(Theme.Opacity.edge)) }
                        .frame(width: max(0, room * shares[i]))
                }
            }
        }
        .frame(width: 40, height: 28)
        .accessibilityHidden(true)
    }
}

private struct ReviewSettingsForm: View {
    @Bindable var model: SettingsModel
    @State private var details = false

    var body: some View {
        let review = $model.settings.review
        Card(clipped: true) {
            FormRow(label: String(localized: .settingsIntervals), detail: model.reviewDays) {
                IntListField(values: review.intervals, unit: String(localized: .settingsUnitDays), range: 1...365)
            }
            FormRow(label: String(localized: .settingsDailyLimit)) {
                let limit = model.settings.review.dailyLimit
                ScrubField(
                    value: Binding(get: { Double(limit ?? 10) }, set: { model.settings.review.dailyLimit = Int($0.rounded()) }),
                    range: 1...50, step: 1, width: 80
                )
                .disabled(limit == nil)
                .opacity(limit == nil ? 0.4 : 1)
                Text(.settingsUnits).foregroundStyle(Theme.Palette.textSecondary)
                Switch(isOn: Binding(get: { limit != nil }, set: { model.settings.review.dailyLimit = $0 ? 10 : nil }))
            }
            DisclosureRow(label: String(localized: .settingsDetails), isOpen: $details, last: true) {
                FormRow(label: String(localized: .settingsExamWindow)) {
                    IntScrub(value: review.examWindowDays, range: 0...30)
                    Text(.settingsUnitDaysBefore).foregroundStyle(Theme.Palette.textSecondary)
                }
                FormRow(label: String(localized: .settingsCardsPerReview)) {
                    IntScrub(value: review.cardsPerReview, range: 1...20)
                    Text(.settingsUnitCards).foregroundStyle(Theme.Palette.textSecondary)
                }
                FormRow(label: String(localized: .settingsSettleAfter), last: true) {
                    IntScrub(value: review.settleAfterPasses, range: 1...5)
                    Text(.settingsUnitPasses).foregroundStyle(Theme.Palette.textSecondary)
                }
            }
        }
    }
}

private struct AboutSettings: View {
    let model: SettingsModel
    @Environment(\.openLink) private var openLink

    var body: some View {
        Card {
            FormRow(label: String(localized: .settingsVersion)) {
                Text(model.version).foregroundStyle(Theme.Palette.textSecondary).textSelection(.enabled)
            }
            Button {
                openLink(.place(.whatsNew))
            } label: {
                CardRow(last: true) {
                    Text(.whatsNewTitle)
                    Spacer(minLength: Theme.Space.s)
                    Image(systemName: "chevron.right").font(Theme.Glyph.small).foregroundStyle(Theme.Palette.textTertiary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.pointing(.plain))
        }
    }
}

private struct NotificationSettingsForm: View {
    @Binding var settings: NotificationSettings

    var body: some View {
        Block(String(localized: .settingsAssignments)) {
            Card {
                FormRow(label: String(localized: .settingsDueAlert), last: !settings.assignmentDue) {
                    Switch(isOn: $settings.assignmentDue)
                }
                if settings.assignmentDue {
                    FormRow(label: String(localized: .settingsAlertLead), last: true) {
                        IntListField(
                            values: $settings.assignmentLeadHours, unit: String(localized: .settingsUnitHoursBefore), range: 1...336)
                    }
                }
            }
        }
        Block(String(localized: .settingsExams)) {
            Card {
                FormRow(label: String(localized: .settingsDayBefore)) {
                    TimeMenu(minute: $settings.examDayBeforeMinute).disabled(!settings.examDayBefore).opacity(
                        settings.examDayBefore ? 1 : 0.4)
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
                FormRow(label: String(localized: .settingsDailyReview)) {
                    TimeMenu(minute: $settings.dailyReviewMinute).disabled(!settings.dailyReview).opacity(settings.dailyReview ? 1 : 0.4)
                    Switch(isOn: $settings.dailyReview)
                }
                FormRow(label: String(localized: .settingsAttendanceAlert), last: true) { Switch(isOn: $settings.attendance) }
            }
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
        let on = model.settings.backup.enabled
        Block(String(localized: .settingsAutoBackup)) {
            Card {
                FormRow(label: String(localized: .settingsDailyBackup)) {
                    Switch(isOn: $model.settings.backup.enabled)
                }
                FormRow(label: String(localized: .settingsLocation), detail: model.backupFolder) {
                    Button(.settingsChange) { picking = true }
                }
                .opacity(on ? 1 : 0.4)
                FormRow(label: String(localized: .settingsLastBackup), detail: model.lastBackup, last: true) {
                    Button(model.backingUp ? .settingsBackingUp : .settingsBackUpNow) {
                        Task { await model.backUpNow() }
                    }
                    .disabled(model.backingUp)
                }
            }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { model.pickBackupFolder(url) }
        }
        Block(
            String(localized: .settingsRestore),
            note: model.archives.count > SettingsModel.archiveLimit
                ? String(localized: .settingsRecentArchives(SettingsModel.archiveLimit)) : nil
        ) {
            Card {
                if model.archives.isEmpty { CardRow(last: true) { EmptyLine(String(localized: .settingsNoBackups)) } }
                let shown = model.shownArchives
                ForEach(Array(shown.enumerated()), id: \.element.url) { i, archive in
                    CardRow(last: i == shown.count - 1) {
                        Text(archive.day.description).monospacedDigit()
                        Spacer()
                        SearchPicker(
                            options: model.restoreOptions, pick: { restore($0, from: archive) },
                            prompt: String(localized: .settingsRestoreCoursePrompt)
                        ) {
                            ChipLabel(String(localized: .settingsRestoreCourse))
                        }
                    }
                }
            }
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
    @Bindable var model: SettingsModel
    @State private var open: Set<NoteKind> = []
    @State private var snippets: MathSyntax?

    static let kinds: [NoteKind] = [.review, .examSummary, .unit]

    var body: some View {
        let settings = $model.settings
        Block(String(localized: .settingsNewNote)) {
            Card(clipped: true) {
                FormRow(label: String(localized: .settingsMathSyntax)) {
                    ChoiceMenu(selection: settings.newNoteMath, options: MathSyntax.allCases.map { ($0, $0.label) })
                }
                ForEach(Self.kinds, id: \.self) { kind in
                    let last = kind == Self.kinds.last
                    DisclosureRow(
                        label: String(localized: .settingsTemplateHeadings(Self.name(kind))),
                        isOpen: Binding(get: { open.contains(kind) }, set: { if $0 { open.insert(kind) } else { open.remove(kind) } }),
                        last: last
                    ) {
                        // 방금 더한 행이 입력할 때까지 남도록 빈 칸까지 담은 목록 그대로 쓴다.
                        HeadingRows(
                            lines: Binding(
                                get: { model.settings.noteTemplates[kind.rawValue] ?? NoteTemplate.defaultSections(for: kind) },
                                set: {
                                    model.settings.noteTemplates[kind.rawValue] = $0 == NoteTemplate.defaultSections(for: kind) ? nil : $0
                                }
                            ), last: last)
                    }
                }
            }
        }
        let shown = snippets ?? model.settings.newNoteMath
        Block(
            title: String(localized: .settingsSnippets),
            trailing: {
                Segmented(
                    selection: Binding(get: { shown }, set: { snippets = $0 }),
                    options: [(.latex, MathSyntax.latex.label), (.asciimath, MathSyntax.asciimath.label)], compact: true)
            }
        ) {
            // 바꾸기 전까지 노트 편집기가 앱 기본값을 계속 받도록, 바꾼 뒤에만 저장한다.
            switch shown {
            case .latex:
                SnippetList(
                    snippets: Binding(
                        get: { model.settings.snippets }, set: { model.settings.mathSnippets = $0 == MathSnippet.defaults ? nil : $0 }))
            case .asciimath:
                SnippetList(
                    snippets: Binding(
                        get: { model.settings.asciiSnippets },
                        set: { model.settings.asciiMathSnippets = $0 == MathSnippet.asciiMathDefaults ? nil : $0 }),
                    defaults: MathSnippet.asciiMathDefaults, placed: false)
            }
        }
    }

    static func name(_ kind: NoteKind) -> String {
        switch kind {
        case .review: String(localized: .settingsTemplateReview)
        case .examSummary: String(localized: .settingsTemplateExamSummary)
        case .unit: String(localized: .settingsTemplateUnit)
        default: ""
        }
    }
}

private struct ClaudeSettings: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Block(String(localized: .settingsConnection)) {
            ClaudeConnectionCard(model: model)
        }
        FormTextArea(label: String(localized: .settingsNoteRules), text: $model.settings.noteRules)
        Block(String(localized: .settingsUsage)) {
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
        .task(model.loadUsage)
    }
}
