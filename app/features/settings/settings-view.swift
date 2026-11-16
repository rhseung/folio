import FolioAI
import FolioDomain
import FolioStorage
import SwiftUI

extension EnvironmentValues {
    @Entry var showSettings: @MainActor (AppLink.SettingsPage) -> Void = { _ in }
}

extension FocusedValues {
    @Entry var showSettings: (@MainActor (AppLink.SettingsPage?) -> Void)?
}

struct SettingsView: View {
    @State private var model: SettingsModel
    @AppStorage(AppLink.SettingsPage.storageKey) private var remembered: AppLink.SettingsPage = .general
    @Environment(\.place) private var place
    @Environment(\.openLink) private var openLink

    init(workspace: Workspace) { _model = State(initialValue: SettingsModel(workspace: workspace, tab: .remembered)) }

    var tab: AppLink.SettingsPage { model.tab }

    // 고를 때만 기억해야, 링크나 뒤로 가기로 탭에 와도 사이드바가 다음에 여는 탭이 바뀌지 않는다.
    func pick(_ t: AppLink.SettingsPage) {
        remembered = t
        openLink(.settings(t))
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

    @ViewBuilder func content(_ tab: AppLink.SettingsPage) -> some View {
        switch tab {
        case .general: GeneralSettings(model: model)
        case .record:
            Block(String(localized: .settingsProfile)) { ProfileCard(workspace: model.workspace) }
            Block(String(localized: .settingsLetters)) { CatalogEditor() }
            SettingBlock(.school, model: model)
        case .classes: ClassSettings(model: model)
        case .notes: NoteSettingsForm(model: model)
        case .review: SettingBlock(.review, model: model)
        case .notifications:
            SettingBlock(.assignmentAlerts, model: model)
            SettingBlock(.examAlerts, model: model)
            SettingBlock(.reviewAlerts, model: model)
        case .claude: ClaudeSettings(model: model)
        case .lms:
            LMSSettingsForm(workspace: model.workspace)
            SettingBlock(.lmsSync, model: model)
        case .backup: BackupSettingsForm(model: model)
        case .about: AboutSettings(model: model)
        }
    }
}

// 그 자리에서 준 `closeColumn`을 페이지 위에 연 열이 읽도록 따로 뷰로 둔다.
private struct SettingsColumn: View {
    let tab: AppLink.SettingsPage
    let pick: (AppLink.SettingsPage) -> Void
    @Environment(\.closeColumn) private var closeColumn

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                Text(.settingsTitle).font(Theme.Typeface.columnTitle).padding(.horizontal, Theme.Inset.listRow.leading)
                VStack(spacing: Theme.Space.m) {
                    ForEach(0..<3, id: \.self) { run in
                        VStack(spacing: Theme.Space.xxs) {
                            ForEach(AppLink.SettingsPage.allCases.filter { $0.run == run }) { t in
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
                    SegmentedControl(
                        selection: $appearance, options: Appearance.allCases.map { ($0, $0.label) },
                        systemImages: Appearance.allCases.map(\.symbol))
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
        SettingBlock(.day, model: model)
        SettingBlock(.deadlines, model: model)
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
                        Select(selection: $model.classStartPreset, options: model.classStartPresets.map { ($0.id, $0.title) })
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
                    if preset.isBuiltIn { Badge(String(localized: .settingsPaneLayoutsBuiltIn)) }
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
        .menuButton(tinted: true, indicator: .hidden).fixedSize()
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
        .frame(Theme.Size.layoutGlyph)
        .accessibilityHidden(true)
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
        DiagnosticReports(workspace: model.workspace)
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
        SettingBlock(.autoBackup, model: model) {
            FormRow(label: String(localized: SettingItem.backupFolder.name), detail: model.backupFolder) {
                Button(.settingsChange) { picking = true }
            }
            .opacity(on ? 1 : Theme.Opacity.disabled)
            FormRow(label: String(localized: .settingsLastBackup), detail: model.lastBackup, last: true) {
                Button(model.backingUp ? .settingsBackingUp : .settingsBackUpNow) {
                    Task { await model.backUpNow() }
                }
                .disabled(model.backingUp)
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
                        CommandList(
                            options: model.restoreOptions, onSelect: { restore($0, from: archive) },
                            prompt: String(localized: .settingsRestoreCoursePrompt)
                        ) {
                            SelectTrigger(String(localized: .settingsRestoreCourse))
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
        SettingBlock(.newNote, model: model) {
            ForEach(Self.kinds, id: \.self) { kind in
                let last = kind == Self.kinds.last
                DisclosureRow(
                    label: String(localized: .settingsTemplateHeadings(Self.name(kind))),
                    isExpanded: Binding(get: { open.contains(kind) }, set: { if $0 { open.insert(kind) } else { open.remove(kind) } }),
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
        let shown = snippets ?? model.settings.newNoteMath
        Block(
            title: String(localized: .settingsSnippets),
            trailing: {
                SegmentedControl(
                    selection: Binding(get: { shown }, set: { snippets = $0 }),
                    options: [(.latex, MathSyntax.latex.label), (.asciimath, MathSyntax.asciimath.label)], size: .small)
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
        CalloutList(model: model)
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
        SettingBlock(.noteRules, model: model)
        Block(String(localized: .settingsUsage)) {
            Card {
                let shown = Array(model.usage.prefix(6))
                if shown.isEmpty { CardRow(last: true) { EmptyLine(String(localized: .settingsNoRequests)) } }
                ForEach(Array(shown.enumerated()), id: \.offset) { i, m in
                    CardRow(last: i == shown.count - 1) {
                        Text(SettingsModel.month(m)).monospacedDigit()
                        Spacer()
                        Text(.settingsRequestCount(m.requests)).monospacedDigit().foregroundStyle(Theme.Palette.textSecondary)
                        Text(m.cost, format: .currency(code: "USD")).monospacedDigit().frame(
                            minWidth: Theme.Size.numberColumn, alignment: .trailing)
                    }
                }
            }
        }
        .task(model.loadUsage)
    }
}
