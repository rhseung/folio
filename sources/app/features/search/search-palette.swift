import FolioDomain
import FolioIndex
import SwiftUI

struct SearchPalette: View {
    @Environment(\.openLink) private var openLink
    @Environment(\.itemSheets) private var sheets
    @State private var model: SearchModel
    let close: () -> Void
    let choose: (AppLink, UUID) -> Void
    @State private var resultsHeight: CGFloat = 0
    @FocusState private var focused: Bool

    init(workspace: Workspace, close: @escaping () -> Void, choose: @escaping (AppLink, UUID) -> Void) {
        _model = State(initialValue: SearchModel(workspace: workspace))
        self.close = close
        self.choose = choose
    }

    static let inset = Theme.Space.s
    static let icon = Theme.Size.tile
    static let radius: CGFloat = Theme.Radius.floating + inset

    var body: some View {
        let groups = model.groups
        let flat = groups.flatMap(\.hits)
        VStack(spacing: 0) {
            HStack(spacing: Theme.Space.m) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .medium))  // design: one-off, sized to the palette field
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .frame(width: Self.icon)
                TextField(String(localized: .searchPrompt), text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20))  // design: one-off, the palette field reads larger than page text, as in Spotlight
                    .focused($focused)
                    .onSubmit { if flat.indices.contains(model.selected) { open(flat[model.selected]) } }
                    .onKeyPress(.downArrow) {
                        model.moveSelection(by: 1); return .handled
                    }
                    .onKeyPress(.upArrow) {
                        model.moveSelection(by: -1); return .handled
                    }
                    .onKeyPress(.escape) {
                        close(); return .handled
                    }
                if model.index == nil {
                    ProgressView().controlSize(.small)
                } else if let indexing = model.indexing {
                    HStack(spacing: Theme.Space.xs) {
                        ProgressView(value: Double(indexing.done), total: Double(max(indexing.total, 1)))
                            .progressViewStyle(.circular).controlSize(.small)
                        Text(.searchIndexing(indexing.done, indexing.total))
                            .font(Theme.Typeface.caption).monospacedDigit()
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                    .help(Text(.searchIndexingHelp))
                }
                SearchSelect(selection: $model.scope, options: model.scopeOptions).font(Theme.Typeface.caption)
            }
            .padding(.horizontal, Self.inset + Theme.Space.s)
            .padding(.vertical, Theme.Space.l + Theme.Space.xs)
            if model.typed {
                Theme.Palette.lineSoft.frame(height: 1)
                kinds
                    .padding(.horizontal, Self.inset + Theme.Space.s)
                    .padding(.top, Theme.Space.m)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                            if flat.isEmpty, model.index != nil {
                                EmptyLine(model.emptyMessage)
                                    .padding(Theme.Space.s)
                            }
                            ForEach(groups, id: \.kind) { group in
                                header(group)
                                ForEach(group.hits, id: \.self) { hit in
                                    let i = flat.firstIndex(of: hit) ?? 0
                                    row(hit, selected: i == model.selected).id(i)
                                }
                            }
                        }
                        .padding(Self.inset)
                        .onGeometryChange(for: CGFloat.self) {
                            $0.size.height
                        } action: {
                            resultsHeight = $0
                        }
                    }
                    .overflowFade(.vertical)
                    // ScrollView는 받은 높이를 모두 차지하므로, 짧은 목록이 짧게 남도록 결과 높이에 맞춘다.
                    .frame(height: min(resultsHeight, 440))
                    .onChange(of: model.selected) { _, new in proxy.scrollTo(new) }
                }
                if !flat.isEmpty { footer }
            }
        }
        .frame(maxWidth: 680)
        .background(Theme.Palette.card, in: .rect(cornerRadius: Self.radius))
        .glassEffect(.regular, in: .rect(cornerRadius: Self.radius))
        .shadow(color: .black.opacity(0.25), radius: 32, y: 16)
        .onChange(of: model.query) { model.refresh() }
        .onChange(of: model.kind) {
            model.refresh(); focused = true
        }
        .onChange(of: model.scope) {
            model.refresh(); focused = true
        }
        .task {
            focused = true
            #if DEBUG && os(macOS)
            if let q = SnapshotDriver.shared.searchQuery { model.query = q }
            #endif
            await model.start()
        }
    }

    var kinds: some View {
        HStack(spacing: Theme.Space.xs) {
            ForEach([nil] + SearchKind.allCases.map(Optional.some), id: \.self) { (k: SearchKind?) in
                let chosen = model.kind == k
                Button {
                    model.kind = k
                } label: {
                    HStack(spacing: Theme.Space.tight) {
                        if let k { Image(systemName: k.symbol).font(Theme.Glyph.regular) }
                        Text(k?.label ?? String(localized: .searchKindAll))
                    }
                    .fontWeight(chosen ? .semibold : .regular)
                    .foregroundStyle(chosen ? Theme.Palette.text : Theme.Palette.textSecondary)
                    .padding(Theme.Inset.toggle)
                    .background(chosen ? Theme.Palette.fill : .clear, in: .capsule)
                    .overlay { if !chosen { Capsule().strokeBorder(Theme.Palette.lineSoft) } }
                    .contentShape(.capsule)
                }
                .buttonStyle(.pointing(.plain))
            }
            Spacer(minLength: 0)
        }
        .font(Theme.Typeface.caption)
    }

    func header(_ group: SearchModel.KindGroup) -> some View {
        HStack {
            Caption(group.kind.label)
            Spacer()
            if group.more > 0 {
                Button(.searchMore(group.kind.label, group.more)) { model.kind = group.kind }
                    .buttonStyle(.ghost)
                    .font(Theme.Typeface.label)
            }
        }
        .padding(.horizontal, Theme.Space.s)
        .padding(.top, Theme.Space.m)
        .padding(.bottom, Theme.Space.xs)
    }

    var footer: some View {
        HStack(spacing: Theme.Space.l) {
            hint("↑↓", String(localized: .searchHintMove))
            hint("↩", String(localized: .commonOpen))
            hint("esc", String(localized: .commonClose))
            Spacer()
        }
        .font(Theme.Typeface.caption)
        .foregroundStyle(Theme.Palette.textTertiary)
        .padding(.horizontal, Self.inset + Theme.Space.s)
        .padding(.vertical, Theme.Space.m)
        .overlay(alignment: .top) { Theme.Palette.lineSoft.frame(height: 1) }
    }

    func hint(_ key: String, _ action: String) -> some View {
        HStack(spacing: Theme.Space.tight) {
            keycap(key)
            Text(action)
        }
    }

    func keycap(_ key: String) -> some View { KeyCap(key) }

    func row(_ hit: SearchHit, selected: Bool) -> some View {
        let course = model.workspace.course(hit.item.courseId)
        let accent = model.workspace.accent(hit.item.courseId)
        return Button {
            open(hit)
        } label: {
            HStack(spacing: Theme.Space.m) {
                LineIcon(symbol: hit.item.kind.symbol).foregroundStyle(accent.ink)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(marked(hit.item.title, color: Theme.Palette.text, match: accent.ink)).font(Theme.Typeface.bodyStrong).lineLimit(1)
                    if let snippet = hit.snippet.map(SearchModel.plain) {
                        Text(marked(snippet, color: Theme.Palette.textTertiary, match: Theme.Palette.text))
                            .font(Theme.Typeface.caption).lineLimit(1)
                    }
                }
                Spacer(minLength: Theme.Space.m)
                if let course {
                    HStack(spacing: Theme.Space.tight) {
                        CourseMark(icon: course.file.course.icon, color: accent.color, inline: true)
                        Text(course.title).lineLimit(1)
                    }
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .frame(maxWidth: 160, alignment: .trailing)
                    .fixedSize(horizontal: false, vertical: true)
                }
                if selected { keycap("↩") }
            }
            .padding(Theme.Space.s)
            .background(selected ? Theme.Palette.fill : .clear, in: .rect(cornerRadius: Theme.Radius.floating))
            .contentShape(.rect)
        }
        .buttonStyle(.pointing(.plain))
        .contextMenu { menu(hit) }
    }

    @ViewBuilder func menu(_ hit: SearchHit) -> some View {
        let item = hit.item
        Group {
            switch item.kind {
            case .session:
                SessionMenu(courseId: item.courseId, sessionId: item.id) {
                    close()
                    openLink(AppLink(.note, $0), course: item.courseId)
                }
            case .note:
                if let course = model.workspace.course(item.courseId), let note = course.store.note(id: item.id, in: course.file) {
                    NoteMenu(courseId: item.courseId, note: note)
                }
            case .material: MaterialMenu(courseId: item.courseId, materialId: item.id)
            case .assignment: AssignmentMenu(courseId: item.courseId, assignmentId: item.id)
            case .exam: ExamMenu(courseId: item.courseId, examId: item.id)
            case .unit: UnitMenu(courseId: item.courseId, unitId: item.id)
            case .quiz:
                Button(.commonOpen, systemImage: "arrow.right.circle") { open(hit) }
                Divider()
                ShareMenu(link: AppLink(item), course: item.courseId)
            }
        }
        .environment(
            \.openLink,
            OpenLinkAction { link, placement, course in
                close()
                openLink(link, in: placement, course: course)
            }
        )
        .environment(
            \.itemSheets,
            ItemSheetsAction(
                present: {
                    close(); sheets.present($0)
                },
                confirm: {
                    close(); sheets.confirm($0)
                }))
    }

    func marked(_ text: String, color: Color, match: Color) -> AttributedString {
        var result = AttributedString(text)
        result.foregroundColor = color
        for word in model.words {
            var from = result.startIndex
            while from < result.endIndex,
                let r = result[from...].range(of: word, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive])
            {
                result[r].foregroundColor = match
                result[r].inlinePresentationIntent = .stronglyEmphasized
                from = r.upperBound
            }
        }
        return result
    }

    func open(_ hit: SearchHit) {
        choose(AppLink(hit.item), hit.item.courseId)
        close()
    }
}
