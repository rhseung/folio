import FolioAI
import FolioDomain
import FolioStorage
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case profile = "내 정보", general = "일반", notifications = "알림", backup = "백업", catalog = "평어", notes = "노트", claude = "Claude"
    var id: Self { self }
    /// Remembered across launches.
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
    /// Opens the settings page at a section, from anywhere in the main window.
    @Entry var showSettings: @MainActor (SettingsTab) -> Void = { _ in }
}

extension FocusedValues {
    /// The window's way to open settings, for the ⌘, menu item.
    @Entry var showSettings: (@MainActor (SettingsTab?) -> Void)?
}

/// docs/SPEC.md "설정". Edits go to a local copy and are saved to settings.json once typing pauses.
struct SettingsView: View {
    @Environment(Workspace.self) private var workspace
    @AppStorage(SettingsTab.storageKey) private var tab: SettingsTab = .general
    @State private var settings = FolioDomain.Settings()
    /// Until the copy is filled from the workspace, saving would write defaults over the real file.
    @State private var loaded = false

    var body: some View {
        // A column of sections beside the page, like a course's column, instead of a separate window with tabs.
        HStack(spacing: 0) {
            column.frame(width: Theme.Size.courseColumn)
            ColumnDivider()
            Page(maxWidth: 640) {
                PageHeader(title: tab.rawValue)
                content(tab)
            }
            // Each section starts at its top, not at the scroll position of the one before.
            .id(tab)
        }
        .onAppear {
            settings = workspace.settings
            loaded = true
        }
        .onChange(of: workspace.settings) { _, new in settings = new }
        .task(id: settings) {
            guard loaded else { return }
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, settings != workspace.settings else { return }
            workspace.saveSettings(settings)
        }
        // Closing right after a change cancels the wait above; save what was left.
        .onDisappear { if loaded, settings != workspace.settings { workspace.saveSettings(settings) } }
    }

    var column: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                Text("설정").font(Theme.Typeface.columnTitle).padding(.horizontal, Theme.Inset.listRow.leading)
                VStack(spacing: Theme.Space.xxs) {
                    ForEach(SettingsTab.allCases) { t in
                        let chosen = tab == t
                        Button { tab = t } label: { ColumnRow(title: t.rawValue, symbol: t.symbol, chosen: chosen) }
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
                ProfileCard()
                Footnote("졸업 요건에는 선언한 과정의 요건만 보입니다. 바꾸면 바로 저장됩니다.")
            }
        case .general: GeneralSettings(settings: $settings)
        case .notifications: NotificationSettingsForm(settings: $settings.notifications)
        case .backup: BackupSettingsForm(settings: $settings.backup)
        case .catalog: CatalogEditor()
        case .notes: NoteSettingsForm(settings: $settings)
        case .claude: ClaudeSettings()
        }
    }
}

private struct GeneralSettings: View {
    @Environment(Workspace.self) private var workspace
    @Binding var settings: FolioDomain.Settings
    @State private var pickingFolder = false
    @AppStorage(Appearance.storageKey) private var appearance: Appearance = .system

    var body: some View {
        Block("화면") {
            Card {
                FormRow(label: "모양", detail: "이 기기에만 적용됩니다", last: true) {
                    Segmented(selection: $appearance, options: Appearance.allCases.map { ($0, $0.label) }, symbols: Appearance.allCases.map(\.symbol))
                }
            }
        }
        Block("GIST 폴더") {
            Card {
                FormRow(label: "위치", detail: workspace.gist.map { ($0.url.path as NSString).abbreviatingWithTildeInPath } ?? "없음", last: true) {
                    Button("다른 폴더 고르기") { pickingFolder = true }
                }
            }
        }
        .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { workspace.open(url) }
        }
        Block("하루와 복습") {
            Card {
                FormRow(label: "하루가 바뀌는 시각", detail: "이 시각 전까지는 전날로 칩니다") {
                    TimeMenu(minute: $settings.dayBoundaryMinutes, hours: 0...8)
                }
                FormRow(label: "하루 복습 상한", detail: "넘는 단원은 우선순위가 낮은 것부터 다음 날로 미룹니다") {
                    let limit = settings.review.dailyLimit
                    ScrubField(value: Binding(get: { Double(limit ?? 10) }, set: { settings.review.dailyLimit = Int($0.rounded()) }),
                               range: 1...50, step: 1, width: 80)
                        .disabled(limit == nil)
                        .opacity(limit == nil ? 0.4 : 1)
                    Text("단원").foregroundStyle(Theme.Palette.textSecondary)
                    Switch(isOn: Binding(get: { limit != nil }, set: { settings.review.dailyLimit = $0 ? 10 : nil }))
                }
                FormRow(label: "복습 간격", detail: "단계마다 며칠 뒤에 다시 볼지", last: true) {
                    IntListField(values: $settings.review.intervals, unit: "일", range: 1...365)
                }
            }
        }
    }
}

private struct NotificationSettingsForm: View {
    @Binding var settings: NotificationSettings

    var body: some View {
        Block("과제") {
            Card {
                FormRow(label: "마감 알림", last: !settings.assignmentDue) { Switch(isOn: $settings.assignmentDue) }
                if settings.assignmentDue {
                    FormRow(label: "알림 시점", detail: "마감 몇 시간 전에 알릴지", last: true) {
                        IntListField(values: $settings.assignmentLeadHours, unit: "시간 전", range: 1...336)
                    }
                }
            }
        }
        Block("시험") {
            Card {
                FormRow(label: "전날") {
                    TimeMenu(minute: $settings.examDayBeforeMinute).disabled(!settings.examDayBefore).opacity(settings.examDayBefore ? 1 : 0.4)
                    Switch(isOn: $settings.examDayBefore)
                }
                FormRow(label: "당일 아침", last: true) {
                    TimeMenu(minute: $settings.examMorningMinute).disabled(!settings.examMorning).opacity(settings.examMorning ? 1 : 0.4)
                    Switch(isOn: $settings.examMorning)
                }
            }
        }
        Block("복습과 출석") {
            Card {
                FormRow(label: "오늘 복습할 단원 수", detail: "하루 한 번") {
                    TimeMenu(minute: $settings.dailyReviewMinute).disabled(!settings.dailyReview).opacity(settings.dailyReview ? 1 : 0.4)
                    Switch(isOn: $settings.dailyReview)
                }
                FormRow(label: "결석이 상한에 한 번 남았을 때", last: true) { Switch(isOn: $settings.attendance) }
            }
            Footnote("알림은 기기마다 따로 보냅니다.")
        }
    }
}

private struct BackupSettingsForm: View {
    @Environment(Workspace.self) private var workspace
    @Binding var settings: BackupSettings
    #if os(macOS)
    @State private var archives: [BackupStore.Archive] = []
    @State private var running = false
    @State private var picking = false
    #endif

    var body: some View {
        #if os(macOS)
        Block("자동 백업") {
            Card {
                FormRow(label: "하루 한 번 자동 백업", detail: "최근 \(settings.dailyDays)일은 매일, 그 전은 주 1회만 남깁니다") {
                    Switch(isOn: $settings.enabled)
                }
                FormRow(label: "위치", detail: (settings.folder as NSString).abbreviatingWithTildeInPath) {
                    Button("바꾸기") { picking = true }
                }
                FormRow(label: "마지막 백업", detail: archives.first.map { "\($0.day)" } ?? "없음", last: true) {
                    Button(running ? "백업 중…" : "지금 백업") {
                        running = true
                        Task {
                            await workspace.backUpNow()
                            running = false
                            refresh()
                        }
                    }
                    .disabled(running)
                }
            }
            Footnote("GIST 폴더의 .folio과 과목마다 Notes, Ink, .folio을 담습니다.")
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            if let gist = workspace.gist, (url.standardizedFileURL.path + "/").hasPrefix(gist.url.standardizedFileURL.path + "/") {
                workspace.error = "백업 위치는 GIST 폴더 밖이어야 합니다."
            } else {
                settings.folder = url.path
            }
        }
        Block("복원", note: archives.count > 12 ? "최근 12개" : nil) {
            Card {
                if archives.isEmpty { CardRow(last: true) { EmptyLine("아직 백업이 없습니다") } }
                ForEach(Array(archives.prefix(12).enumerated()), id: \.element.url) { i, archive in
                    CardRow(last: i == min(archives.count, 12) - 1) {
                        Text(archive.day.description).monospacedDigit()
                        Spacer()
                        SearchPicker(options: workspace.semesters.flatMap { s in workspace.courses(in: s).map { PickOption(id: $0.id, title: $0.title, section: s.title) } },
                                     pick: { restore($0, from: archive) }, prompt: "복원할 과목") {
                            ChipLabel("과목 복원")
                        }
                    }
                }
            }
            Footnote("고른 과목의 Notes, Ink, .folio을 백업 폴더 옆 restored 폴더에 새로 꺼냅니다. GIST 폴더는 건드리지 않습니다.")
        }
        .onAppear(perform: refresh)
        .onChange(of: workspace.settings.backup) { _, _ in refresh() }
        #else
        Block("백업") {
            Card { CardRow(last: true) { EmptyLine("백업은 Mac 앱이 맡습니다") } }
        }
        #endif
    }

    #if os(macOS)
    func refresh() {
        archives = workspace.backupStore?.archives() ?? []
    }

    func restore(_ course: UUID, from archive: BackupStore.Archive) {
        Task {
            if let folder = await workspace.restore(course, from: archive) {
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
            Block("\(Self.names[kind] ?? "") 템플릿", note: kind == .review ? "새 노트의 소제목, 위에서부터. 러프와 자유 노트는 빈 본문으로 시작합니다" : nil) {
                // The raw list, blanks included, so a row just added stays until it's typed into.
                HeadingList(lines: Binding(
                    get: { settings.noteTemplates[kind.rawValue] ?? NoteTemplate.defaultSections(for: kind) },
                    set: { settings.noteTemplates[kind.rawValue] = $0 == NoteTemplate.defaultSections(for: kind) ? nil : $0 }
                ))
            }
        }
        Block("수식", note: "새로 만드는 노트에 씁니다. 이미 있는 노트는 편집기 위쪽에서 노트마다 바꿉니다") {
            Card {
                FormRow(label: "수식 문법", detail: "AsciiMath는 x^2/2, sum_(i=1)^n처럼 씁니다", last: true) {
                    ChoiceMenu(selection: $settings.newNoteMath, options: MathSyntax.allCases.map { ($0, $0.label) })
                }
            }
        }
        FormTextArea(label: "노트 작성 규칙", detail: "Claude가 노트를 쓸 때 항상 맥락에 넣습니다", text: $settings.noteRules, height: 160)
    }

    static let names: [NoteKind: String] = [.review: "복습 노트", .examSummary: "시험 종합 정리", .topic: "단원 정리"]
}

private struct ClaudeSettings: View {
    @Environment(Workspace.self) private var workspace
    @State private var apiKey = ""
    @State private var keySaved = APIKeyStore.read() != nil
    @AppStorage(Workspace.subscriptionKey) private var subscription = true
    /// Read once per visit: it parses every course's log file.
    @State private var usage: [MonthlyUsage] = []

    var body: some View {
        Block("연결") {
            Card {
                #if os(macOS)
                let cli = CLIProvider.find()
                FormRow(label: "연결 방식", detail: subscription ? (cli.map { "\($0.path) · 도구 없이 답만 받습니다" } ?? "claude를 찾지 못했습니다. Claude Code를 설치하고 로그인하세요")
                                                          : "아래 API 키로 연결합니다. iPad는 항상 이 방식입니다") {
                    ChoiceMenu(selection: $subscription, options: [(true, "Claude Code 구독"), (false, "API 키")])
                }
                .onChange(of: subscription) { workspace.claudeRevision += 1 }
                #endif
                FormRow(label: "API 키", detail: "키체인에 저장되고 iCloud 키체인으로 다른 기기와 공유됩니다", last: true) {
                    SecureField(keySaved ? "저장됨" : "sk-ant-…", text: $apiKey).pill(width: 180).onSubmit(saveKey)
                    Button("저장", action: saveKey).disabled(apiKey.isEmpty)
                }
            }
        }
        Block("사용량", note: "월별 요청 수와 예상 비용") {
            Card {
                if usage.isEmpty { CardRow(last: true) { EmptyLine("아직 보낸 요청이 없습니다") } }
                ForEach(Array(usage.prefix(6).enumerated()), id: \.offset) { i, m in
                    CardRow(last: i == min(usage.count, 6) - 1) {
                        Text("\(String(m.year))년 \(m.month)월").monospacedDigit()
                        Spacer()
                        Text("\(m.requests)회").monospacedDigit().foregroundStyle(Theme.Palette.textSecondary)
                        Text(m.cost, format: .currency(code: "USD")).monospacedDigit().frame(minWidth: 72, alignment: .trailing)
                    }
                }
            }
        }
        .task { usage = workspace.monthlyAPIUsage() }
    }

    func saveKey() {
        guard !apiKey.isEmpty else { return }
        workspace.perform {
            // folio:not-an-action the API key goes to the keychain
            try APIKeyStore.save(apiKey)
            apiKey = ""
            keySaved = true
            workspace.claudeRevision += 1
        }
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

/// On/off switch at the right of a form row.
struct Switch: View {
    @Binding var isOn: Bool
    var body: some View {
        Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch)
    }
}

/// Whole numbers as chips, each removable; a new one is scrubbed in a popover, held to `range`.
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
                        .help("빼기")
                    }
                }
                .chip()
                .fixedSize()
                .contextMenu {
                    // Never empty: the last value stays, as its × does.
                    Button("빼기", role: .destructive) { values.removeAll { $0 == v } }.disabled(values.count < 2)
                }
            }
            Button {
                draft = min((values.last ?? 0) + 1, range.upperBound)
                adding = true
            } label: { Image(systemName: "plus") }
            .buttonStyle(.ghost)
            .help("추가")
            .popover(isPresented: $adding) {
                HStack(spacing: Theme.Space.s) {
                    ScrubField(value: Binding(get: { Double(draft) }, set: { draft = min(max(Int($0.rounded()), range.lowerBound), range.upperBound) }),
                               range: Double(range.lowerBound)...Double(range.upperBound), step: 1, width: 88)
                    Text(unit).foregroundStyle(Theme.Palette.textSecondary)
                    Button("추가", action: add).buttonStyle(.pointing(.borderedProminent))
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

/// One heading per row, in order, each editable and removable.
struct HeadingList: View {
    @Binding var lines: [String]

    var body: some View {
        Card {
            ForEach(lines.indices, id: \.self) { i in
                CardRow {
                    Text("\(i + 1)").monospacedDigit().foregroundStyle(Theme.Palette.textTertiary).frame(width: 18, alignment: .trailing)
                    // Guarded: a removed row can still be asked for its text once while the list redraws.
                    TextField("소제목", text: Binding(get: { lines.indices.contains(i) ? lines[i] : "" }, set: { if lines.indices.contains(i) { lines[i] = $0 } }))
                        .textFieldStyle(.plain)
                    Button { lines.remove(at: i) } label: {
                        Image(systemName: "minus.circle").foregroundStyle(Theme.Palette.textTertiary)
                    }
                    .buttonStyle(.pointing(.plain))
                    .help("삭제")
                }
                .contextMenu { Button("삭제", role: .destructive) { if lines.indices.contains(i) { lines.remove(at: i) } } }
            }
            CardRow(last: true) {
                Button { lines.append("") } label: {
                    Label("소제목 추가", systemImage: "plus").foregroundStyle(Theme.Palette.textSecondary)
                }
                .buttonStyle(.pointing(.plain))
            }
        }
    }
}
