import FolioDomain
import FolioIndex
import SwiftUI

/// Where a search result leads inside a course.
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

extension SearchKind {
    var label: String {
        switch self {
        case .note: "노트"
        case .material: "자료"
        case .assignment: "과제"
        // Recitations and labs are sessions too; the course pages call them all 회차.
        case .session: "회차"
        case .unit: "단원"
        case .quiz: "퀴즈"
        }
    }

    var symbol: String {
        switch self {
        case .note: "doc.text"
        case .material: "doc"
        case .assignment: "checklist"
        case .session: "calendar"
        case .unit: "list.bullet"
        case .quiz: "rectangle.on.rectangle"
        }
    }

    var section: CourseSection {
        switch self {
        case .note: .notes
        case .material: .materials
        case .assignment: .assignments
        case .session: .sessions
        case .unit: .units
        case .quiz: .quizCards
        }
    }
}

/// ⌘K: one field over every course's notes, files, assignments, sessions, units and quiz cards, grouped by kind and narrowed by
/// kind, semester or course (docs/SPEC.md "검색").
struct SearchPalette: View {
    @Environment(Workspace.self) private var workspace
    let close: () -> Void
    let choose: (SearchTarget) -> Void
    @State private var query = ""
    @State private var kind: SearchKind?
    @State private var scope = Scope.all
    @State private var index: SearchStore?
    @State private var searching: Task<Void, Never>?
    /// Courses read so far and to read while the index catches up; nil once it has.
    @State private var indexing: (done: Int, total: Int)?
    /// Progress hops arrive as separate main-actor tasks and may land after the refresh returned; past that they're stale.
    @State private var caughtUp = false
    @State private var hits: [SearchHit] = []
    @State private var selected = 0
    @State private var resultsHeight: CGFloat = 0
    @FocusState private var focused: Bool

    enum Scope: Hashable {
        case all, semester(UUID), course(UUID)
    }

    struct KindGroup {
        let kind: SearchKind
        let hits: [SearchHit]
        /// Hits of this kind beyond the ones shown.
        let more: Int
    }

    static let perKind = 8
    /// Results sit this far in from the card's edge; the field and the kinds line up with the rows inside it.
    static let inset = Theme.Space.s
    /// The icon column: the magnifier and every result's tile.
    static let icon = Theme.Size.tile
    static let radius: CGFloat = Theme.Radius.floating + inset

    var body: some View {
        let groups = grouped(hits)
        let flat = groups.flatMap(\.hits)
        let typed = !query.trimmingCharacters(in: .whitespaces).isEmpty
        VStack(spacing: 0) {
            HStack(spacing: Theme.Space.m) {
                // In the results' icon column, so the query starts where the result titles do.
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .medium)) // design: one-off, sized to the palette field
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .frame(width: Self.icon)
                TextField("노트, 자료, 과제, 회차, 단원 검색", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20)) // design: one-off, the palette field reads larger than page text, as in Spotlight
                    .focused($focused)
                    .onSubmit { if flat.indices.contains(selected) { open(flat[selected]) } }
                    .onKeyPress(.downArrow) { selected = min(selected + 1, max(flat.count - 1, 0)); return .handled }
                    .onKeyPress(.upArrow) { selected = max(selected - 1, 0); return .handled }
                    .onKeyPress(.escape) { close(); return .handled }
                if index == nil {
                    ProgressView().controlSize(.small)
                } else if let indexing {
                    HStack(spacing: Theme.Space.xs) {
                        ProgressView(value: Double(indexing.done), total: Double(max(indexing.total, 1)))
                            .progressViewStyle(.circular).controlSize(.small)
                        Text("색인 중 \(indexing.done)/\(indexing.total)")
                            .font(Theme.Typeface.caption).monospacedDigit()
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                    .help("바뀐 과목의 노트와 PDF 본문을 읽고 있습니다. 결과가 더 늘어날 수 있습니다")
                }
                SearchSelect(selection: $scope, options: scopeOptions).font(Theme.Typeface.caption)
            }
            .padding(.horizontal, Self.inset + Theme.Space.s)
            .padding(.vertical, Theme.Space.l + Theme.Space.xs)
            // Untyped, the palette is the field alone, like Spotlight; the kinds come with something to narrow.
            if typed {
                Theme.Palette.lineSoft.frame(height: 1)
                kinds
                    .padding(.horizontal, Self.inset + Theme.Space.s)
                    .padding(.top, Theme.Space.m)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                            if flat.isEmpty, index != nil {
                                EmptyLine(indexing != nil ? "아직 색인 중입니다. 다 읽으면 결과가 나올 수 있습니다"
                                          : kind == nil && scope == .all ? "결과가 없습니다" : "결과가 없습니다. 거르는 조건을 넓혀 보세요")
                                    .padding(Theme.Space.s)
                            }
                            ForEach(groups, id: \.kind) { group in
                                header(group)
                                ForEach(group.hits, id: \.self) { hit in
                                    let i = flat.firstIndex(of: hit) ?? 0
                                    row(hit, selected: i == selected).id(i)
                                }
                            }
                        }
                        .padding(Self.inset)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { resultsHeight = $0 }
                    }
                    // A ScrollView takes all the height it is offered; size it to its results so a short list stays short.
                    .frame(height: min(resultsHeight, 440))
                    .onChange(of: selected) { _, new in proxy.scrollTo(new) }
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
        .onChange(of: query) { refresh() }
        // A click on a filter takes focus from the field, and with it the arrow keys and return.
        .onChange(of: kind) { refresh(); focused = true }
        .onChange(of: scope) { refresh(); focused = true }
        .task {
            focused = true
            #if DEBUG && os(macOS)
            if let q = SnapshotDriver.shared.searchQuery { query = q }
            #endif
            // What is already indexed answers at once; changed courses are read again behind it, then the results follow.
            guard let gist = workspace.gist, let store = try? SearchStore.local(for: gist) else { return }
            index = store
            refresh()
            // Each course read shows up in the results as it lands, not only at the end.
            await Task.detached {
                _ = try? store.refresh(gist) { done, total in
                    Task { @MainActor in
                        guard !caughtUp else { return }
                        indexing = done < total ? (done, total) : nil
                        if done > 0 { refresh(keepSelection: true) }
                    }
                }
            }.value
            caughtUp = true
            indexing = nil
            refresh(keepSelection: true)
        }
    }

    /// Loose chips, not `Segmented`: a gray track inside the floating card read as a second, heavier field.
    var kinds: some View {
        HStack(spacing: Theme.Space.xs) {
            ForEach([nil] + SearchKind.allCases.map(Optional.some), id: \.self) { (k: SearchKind?) in
                let chosen = kind == k
                Button { kind = k } label: {
                    HStack(spacing: Theme.Space.tight) {
                        if let k { Image(systemName: k.symbol).font(Theme.Glyph.regular) }
                        Text(k?.label ?? "전체")
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

    /// Every course, then the semesters that hold them, newest first.
    var scopeOptions: [PickOption<Scope>] {
        let semesters = workspace.semesters.filter { !workspace.courses(in: $0).isEmpty }
        return [PickOption(id: .all, title: "모든 과목")]
            + semesters.map { PickOption(id: .semester($0.id), title: $0.title, section: "학기") }
            + semesters.flatMap { s in
                workspace.courses(in: s).map { PickOption(id: .course($0.id), title: $0.title, detail: s.title, section: "과목") }
            }
    }

    func header(_ group: KindGroup) -> some View {
        HStack {
            Caption(group.kind.label)
            Spacer()
            if group.more > 0 {
                Button("\(group.kind.label) \(group.more)개 더") { kind = group.kind }
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
            hint("↑↓", "이동")
            hint("↩", "열기")
            hint("esc", "닫기")
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

    /// Searched once per change of the query or a filter, not per redraw: every keystroke and arrow press redraws.
    /// Off the main actor, since a word shorter than three letters scans every PDF's text.
    func refresh(keepSelection: Bool = false) {
        if !keepSelection { selected = 0 }
        guard let index else { return }
        let courses: Set<UUID>? = switch scope {
        case .all: nil
        case .course(let id): [id]
        case .semester(let id): Set(workspace.courses.filter { $0.file.course.semesterId == id }.map(\.id))
        }
        let (query, kinds, limit) = (query, kind.map { Set([$0]) }, kind == nil ? 60 : 200)
        searching?.cancel()
        searching = Task {
            let found = await Task.detached { (try? index.search(query, kinds: kinds, courses: courses, limit: limit)) ?? [] }.value
            if !Task.isCancelled { hits = found }
        }
    }

    /// Kinds in the order their best hit ranks, each capped so one kind can't push the rest out of view;
    /// with one kind chosen, all of it.
    func grouped(_ hits: [SearchHit]) -> [KindGroup] {
        var order: [SearchKind] = []
        var byKind: [SearchKind: [SearchHit]] = [:]
        for hit in hits {
            if byKind[hit.item.kind] == nil { order.append(hit.item.kind) }
            byKind[hit.item.kind, default: []].append(hit)
        }
        let cap = kind == nil ? Self.perKind : .max
        return order.map { k in
            let all = byKind[k]!
            return KindGroup(kind: k, hits: Array(all.prefix(cap)), more: max(all.count - cap, 0))
        }
    }

    func row(_ hit: SearchHit, selected: Bool) -> some View {
        let course = workspace.course(hit.item.courseId)
        let accent = workspace.accent(hit.item.courseId)
        return Button { open(hit) } label: {
            HStack(spacing: Theme.Space.m) {
                LineIcon(symbol: hit.item.kind.symbol).foregroundStyle(accent.ink)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(marked(hit.item.title, color: Theme.Palette.text, match: accent.ink)).font(Theme.Typeface.bodyStrong).lineLimit(1)
                    if let snippet = hit.snippet.map(Self.plain) {
                        Text(marked(snippet, color: Theme.Palette.textTertiary, match: Theme.Palette.text))
                            .font(Theme.Typeface.caption).lineLimit(1)
                    }
                }
                Spacer(minLength: Theme.Space.m)
                if let course {
                    HStack(spacing: Theme.Space.tight) {
                        CourseDot(color: accent.color)
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
        .contextMenu { Button("열기", systemImage: "arrow.right.circle") { open(hit) } }
    }

    /// The query's words picked out in `match`, so a long snippet shows at once why it was found.
    func marked(_ text: String, color: Color, match: Color) -> AttributedString {
        var result = AttributedString(text)
        result.foregroundColor = color
        for word in query.precomposedStringWithCanonicalMapping.split(whereSeparator: \.isWhitespace) {
            var from = result.startIndex
            while from < result.endIndex,
                  let r = result[from...].range(of: String(word), options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) {
                result[r].foregroundColor = match
                result[r].inlinePresentationIntent = .stronglyEmphasized
                from = r.upperBound
            }
        }
        return result
    }

    /// A note's snippet without its markdown: `**bold**`, `[[link]]` and `![](assets/…)` read as noise in one line.
    static func plain(_ snippet: String) -> String {
        snippet
            .replacingOccurrences(of: #"!?\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
            // The tail of a link the snippet cut into: `…0](assets/x.png)`.
            .replacingOccurrences(of: #"\]\([^)\s]*\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\[\[([^\]|]*)(\|[^\]]*)?\]\]"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"(^|\s)#{1,6}\s"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\*\*|__|`"#, with: "", options: .regularExpression)
    }

    func open(_ hit: SearchHit) {
        let item = hit.item
        choose(SearchTarget(courseId: item.courseId, section: item.kind.section,
                            noteId: item.kind == .note ? item.id : nil, materialId: item.kind == .material ? item.id : nil))
        close()
    }
}
