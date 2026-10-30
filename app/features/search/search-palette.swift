import FolioDomain
import FolioIndex
import SwiftUI

struct SearchTarget: Equatable {
    var courseId: UUID
    var section: CourseSection
    var noteId: UUID?
    var materialId: UUID?
}

extension EnvironmentValues {
    /// Set by RootView when a result is chosen. The course screen that acts on it sets it back to nil,
    /// so leaving and re-entering a section doesn't replay an old jump.
    @Entry var searchTarget: Binding<SearchTarget?> = .constant(nil)
    /// A person to show on 교수와 조교, set from anywhere a name is shown; PeopleView picks it up and clears it.
    @Entry var personTarget: Binding<UUID?> = .constant(nil)
}

struct SearchPalette: View {
    @State private var model: SearchModel
    let close: () -> Void
    let choose: (SearchTarget) -> Void
    @State private var resultsHeight: CGFloat = 0
    @FocusState private var focused: Bool

    init(workspace: Workspace, close: @escaping () -> Void, choose: @escaping (SearchTarget) -> Void) {
        _model = State(initialValue: SearchModel(workspace: workspace))
        self.close = close
        self.choose = choose
    }

    /// Results sit this far in from the card's edge; the field and the kinds line up with the rows inside it.
    static let inset = Theme.Space.s
    /// The icon column: the magnifier and every result's tile.
    static let icon = Theme.Size.tile
    static let radius: CGFloat = Theme.Radius.floating + inset

    var body: some View {
        let groups = model.groups
        let flat = groups.flatMap(\.hits)
        VStack(spacing: 0) {
            HStack(spacing: Theme.Space.m) {
                // In the results' icon column, so the query starts where the result titles do.
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .medium)) // design: one-off, sized to the palette field
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .frame(width: Self.icon)
                TextField(String(localized: .searchPrompt), text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20)) // design: one-off, the palette field reads larger than page text, as in Spotlight
                    .focused($focused)
                    .onSubmit { if flat.indices.contains(model.selected) { open(flat[model.selected]) } }
                    .onKeyPress(.downArrow) { model.moveSelection(by: 1); return .handled }
                    .onKeyPress(.upArrow) { model.moveSelection(by: -1); return .handled }
                    .onKeyPress(.escape) { close(); return .handled }
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
            // Untyped, the palette is the field alone, like Spotlight; the kinds come with something to narrow.
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
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { resultsHeight = $0 }
                    }
                    // A ScrollView takes all the height it is offered; size it to its results so a short list stays short.
                    .frame(height: min(resultsHeight, 440))
                    .onChange(of: model.selected) { _, new in proxy.scrollTo(new) }
                }
                if !flat.isEmpty { footer }
            }
        }
        .frame(width: 680)
        // Opaque: the page behind must not read through the results. Rounder than other floating cards, and
        // concentric with the selected row inside it (radius minus the results' inset).
        .background(Theme.Palette.card, in: .rect(cornerRadius: Self.radius))
        .glassEffect(.regular, in: .rect(cornerRadius: Self.radius))
        .shadow(color: .black.opacity(0.25), radius: 32, y: 16)
        .onChange(of: model.query) { model.refresh() }
        // A click on a filter takes focus from the field, and with it the arrow keys and return.
        .onChange(of: model.kind) { model.refresh(); focused = true }
        .onChange(of: model.scope) { model.refresh(); focused = true }
        .task {
            focused = true
            #if DEBUG && os(macOS)
            if let q = SnapshotDriver.shared.searchQuery { model.query = q }
            #endif
            await model.start()
        }
    }

    /// Loose chips, not `Segmented`: a gray track inside the floating card read as a second, heavier field.
    var kinds: some View {
        HStack(spacing: Theme.Space.xs) {
            ForEach([nil] + SearchKind.allCases.map(Optional.some), id: \.self) { (k: SearchKind?) in
                let chosen = model.kind == k
                Button { model.kind = k } label: {
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

    func keycap(_ key: String) -> some View {
        Text(key).font(Theme.Typeface.label).monospaced()
            .foregroundStyle(Theme.Palette.textSecondary)
            .padding(.horizontal, Theme.Space.tight).padding(.vertical, Theme.Space.xxs)
            .background(Theme.Palette.fill, in: .rect(cornerRadius: Theme.Radius.small))
    }

    func row(_ hit: SearchHit, selected: Bool) -> some View {
        let course = model.workspace.course(hit.item.courseId)
        let accent = model.workspace.accent(hit.item.courseId)
        return Button { open(hit) } label: {
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
        .contextMenu { Button(.commonOpen, systemImage: "arrow.right.circle") { open(hit) } }
    }

    /// The query's words picked out in `match`, so a long snippet shows at once why it was found.
    func marked(_ text: String, color: Color, match: Color) -> AttributedString {
        var result = AttributedString(text)
        result.foregroundColor = color
        for word in model.words {
            var from = result.startIndex
            while from < result.endIndex,
                  let r = result[from...].range(of: word, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) {
                result[r].foregroundColor = match
                result[r].inlinePresentationIntent = .stronglyEmphasized
                from = r.upperBound
            }
        }
        return result
    }

    func open(_ hit: SearchHit) {
        choose(model.target(hit))
        close()
    }
}
