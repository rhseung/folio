import FolioActions
import FolioDomain
import FolioMarkdown
import FolioStorage
import SwiftUI

struct NoteList: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.accent) private var accent
    let course: LoadedCourse
    @Binding var selection: UUID?
    @State private var notes: [NoteFile] = []
    @State private var filter: NoteKind?
    @State private var newTitle = ""
    @State private var adding = false
    @FocusState private var titleFocused: Bool
    @State private var deleting: NoteFile?

    struct Row: Identifiable {
        let note: NoteFile
        let detail: String?
        var id: URL { note.url }
    }

    struct Part: Identifiable {
        let title: String
        let rows: [Row]
        var id: String { title }
    }

    var body: some View {
        let shown = notes.filter { filter == nil || $0.meta.kind == filter }
        let sections = Self.sections(shown, file: course.file)
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            HStack {
                Caption("노트 \(shown.count)")
                Spacer()
                ChoiceMenu(selection: $filter, options: [(NoteKind?.none, "전체")] + NoteKind.allCases.map { (Optional($0), $0.label) })
                Button { adding.toggle() } label: { Image(systemName: "plus") }
                    .buttonStyle(.ghost)
                    .help(filter.map { "새 \($0.label) 노트" } ?? "새 자유 노트")
            }
            .padding(.horizontal, Theme.Space.s)
            .padding(.bottom, Theme.Space.xs)
            if adding {
                TextField(filter.map { "새 \($0.label) 노트 제목" } ?? "새 노트 제목", text: $newTitle)
                    .textFieldStyle(.plain)
                    .focused($titleFocused)
                    .padding(Theme.Inset.listRow)
                    .background(Theme.Palette.card, in: .rect(cornerRadius: Theme.Radius.control))
                    .onSubmit(create)
                    .onKeyPress(.escape) { adding = false; return .handled }
                    .onAppear { titleFocused = true }
            }
            if shown.isEmpty {
                Text(filter.map { "\($0.label) 노트가 없습니다" } ?? "노트가 없습니다. + 로 새로 만듭니다.")
                    .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                    .padding(Theme.Inset.listRow)
            }
            ForEach(sections) { section in
                // One kind chosen in the filter is one section; its heading would only repeat the filter.
                if sections.count > 1 {
                    Caption("\(section.title) \(section.rows.count)")
                        .padding(.horizontal, Theme.Space.s).padding(.top, Theme.Space.m).padding(.bottom, Theme.Space.xxs)
                }
                ForEach(section.rows) { row($0) }
            }
        }
        .confirmationDialog("‘\(deleting?.title ?? "")’ 노트를 삭제할까요?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("휴지통으로 옮기기", role: .destructive) {
                guard let note = deleting else { return }
                workspace.deleteNote(note, course: course)
                if note.meta.id != nil && note.meta.id == selection { selection = nil }
                reload()
            }
        } message: {
            Text("노트 파일을 휴지통으로 옮기고, 이 노트를 러프나 복습 노트로 쓰던 회차에서 연결을 뺍니다. 휴지통에서 되살릴 수 있고, 노트에 넣은 그림은 assets 폴더에 그대로 둡니다.")
        }
        // Notes made elsewhere (the Claude panel) and links changed in the editor show up here too.
        .onChange(of: selection) { _, id in if let id, !notes.contains(where: { $0.meta.id == id }) { reload() } }
        .onChange(of: workspace.notesRevision) { reload() }
        .task(id: course.id) {
            reload()
            #if DEBUG && os(macOS)
            if SnapshotDriver.directory != nil, selection == nil { selection = Self.sections(notes, file: course.file).first?.rows.first?.note.meta.id }
            #endif
        }
    }

    func row(_ row: Row) -> some View {
        let note = row.note
        let selected = note.meta.id != nil && note.meta.id == selection
        return Button { open(note) } label: {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(note.title).lineLimit(1)
                if let detail = row.detail {
                    Text(detail).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
                }
            }
            .fontWeight(selected ? .semibold : .regular)
            .padding(Theme.Inset.listRow)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? accent.tint : .clear, in: .rect(cornerRadius: Theme.Radius.control))
            .contentShape(.rect)
        }
        .buttonStyle(.pointing(.plain))
        .help(note.title)
        .contextMenu {
            Button("열기") { open(note) }
            Divider()
            Button("노트 삭제…", systemImage: "trash", role: .destructive) { deleting = note }
        }
    }

    /// The session a note belongs to is the one pointing at it (what the sessions page reads), else its frontmatter's.
    static func sections(_ notes: [NoteFile], file: CourseFile) -> [Part] {
        let pointed = Dictionary(file.sessions.flatMap { s in [s.roughNoteId, s.reviewNoteId].compactMap { $0 }.map { ($0, s) } }) { a, _ in a }
        func session(_ n: NoteFile) -> Session? {
            n.meta.id.flatMap { pointed[$0] } ?? n.meta.sessionId.flatMap { id in file.sessions.first { $0.id == id } }
        }
        func byTitle(_ a: NoteFile, _ b: NoteFile) -> Bool { a.title.localizedStandardCompare(b.title) == .orderedAscending }
        // A note moved in from an old folder has no ID until opened; it says so instead of a kind it doesn't have yet.
        func detail(_ n: NoteFile, _ text: String?) -> String? { n.meta.id == nil ? "열면 ID가 붙습니다" : text }

        let classNotes = notes.filter { $0.meta.kind == .rough || $0.meta.kind == .review }
            .map { (note: $0, session: session($0)) }
            .sorted { a, b in
                switch (a.session, b.session) {
                case let (x?, y?) where x.id != y.id: x.date > y.date
                case (_?, nil): true
                case (nil, _?): false
                default: a.note.meta.kind == b.note.meta.kind ? byTitle(a.note, b.note) : a.note.meta.kind == .rough
                }
            }
            .map { n, s in
                Row(note: n, detail: detail(n, s.map { "\($0.date.formatted(.dateTime.month().day().weekday())) · \(n.meta.kind.label)" } ?? "\(n.meta.kind.label) · 회차 없음"))
            }

        let exams = notes.filter { $0.meta.kind == .examSummary }
            .map { n in (note: n, exam: file.exams.first { $0.id == n.meta.examId }) }
            .sorted { a, b in
                let (x, y) = (a.exam?.start ?? .distantFuture, b.exam?.start ?? .distantFuture)
                return x != y ? x < y : byTitle(a.note, b.note)
            }
            .map { n, e in Row(note: n, detail: detail(n, e.map { $0.title.isEmpty ? $0.kind.label : $0.title } ?? "시험 없음")) }

        let units = UnitTree.outline(file.units).map(\.unit)
        let topics = notes.filter { $0.meta.kind == .topic }.sorted(by: byTitle).map { n in
            Row(note: n, detail: detail(n, units.filter { n.meta.unitIds.contains($0.id) }.map(\.title).joined(separator: ", ").nilIfEmpty ?? "단원 없음"))
        }

        let free = notes.filter { $0.meta.kind == .free }.sorted(by: byTitle).map { n in
            Row(note: n, detail: detail(n, n.meta.tags.isEmpty ? nil : n.meta.tags.map { "#" + $0 }.joined(separator: " ")))
        }

        return [Part(title: "수업 노트", rows: classNotes), Part(title: "시험 종합 정리", rows: exams),
                Part(title: "단원 정리", rows: topics), Part(title: "자유 노트", rows: free)].filter { !$0.rows.isEmpty }
    }

    func open(_ note: NoteFile) {
        if let id = note.meta.id { selection = id; return }
        guard let path = course.store.coursePath(of: note.url), let id = workspace.run(NoteAdopt(course: course.id, note: path))?.made else { return }
        reload()
        selection = id
    }

    func reload() {
        notes = (try? course.store.notes()) ?? []
    }

    func create() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, let id = workspace.run(NoteAdd(course: course.id, title: title, kind: filter ?? .free))?.made else { return }
        newTitle = ""
        adding = false
        reload()
        selection = id
    }
}

struct NotesView: View {
    let course: LoadedCourse
    let selection: UUID?
    var insert: Binding<String?> = .constant(nil)
    let open: (UUID) -> Void

    var body: some View {
        if let selection, let note = try? course.store.note(id: selection) {
            NoteEditor(store: course.store, courseId: course.id, note: note, insert: insert) { title in
                // Links name a note by its title (Obsidian style); Obsidian also matches case-insensitively.
                let notes = (try? course.store.notes()) ?? []
                if let id = (notes.first { $0.title == title } ?? notes.first { $0.title.caseInsensitiveCompare(title) == .orderedSame })?.meta.id {
                    open(id)
                }
            }
            .id(note.url)
        } else {
            ContentUnavailableView("노트를 고르세요", systemImage: "doc.text", description: Text("왼쪽 목록에서 노트를 고르거나 + 로 새로 만듭니다."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.Palette.page)
        }
    }
}

/// The frontmatter (tags, aliases, IDs) is kept aside and written back unchanged, except the math syntax set here.
struct NoteEditor: View {
    enum Mode: Hashable { case read, live, source }

    @Environment(Workspace.self) private var workspace
    @Environment(\.accent) private var accent
    @Environment(\.scenePhase) private var scenePhase
    let store: CourseStore
    let courseId: UUID
    let note: NoteFile
    var insert: Binding<String?> = .constant(nil)
    let openNote: (String) -> Void
    @State private var frontmatter = Frontmatter()
    @State private var meta = NoteMeta()
    @State private var body_ = ""
    @State private var saved = ""
    @State private var savedMath = MathSyntax.latex
    @State private var mode = Mode.live
    @State private var showsAssets = false
    @State private var pendingInsert: String?
    @State private var assetsRevision = 0
    /// The file as last read or written here. A save finding something else on disk was changed elsewhere (another
    /// device, the CLI) and asks before overwriting it.
    @State private var onDisk = ""
    @State private var conflict = false

    var dirty: Bool { body_ != saved || meta.math != savedMath }

    var body: some View {
        VStack(spacing: 0) {
            PageBar {
                Segmented(selection: $mode, options: [(.read, "읽기"), (.live, "편집"), (.source, "원문")], compact: true)
            } trailing: {
                // Where the writing happens, so finishing it is one click here rather than a trip back to Today.
                if let session = workspace.course(courseId)?.file.sessions.first(where: { meta.id != nil && $0.reviewNoteId == meta.id }), session.reviewNoteUnfinished {
                    Button { workspace.setReviewNoteUnfinished(false, of: session.id, in: courseId) } label: {
                        Label("작성 완료", systemImage: "checkmark.circle").labelStyle(.titleAndIcon).padding(.horizontal, Theme.Space.s)
                    }
                    .help("복습 노트를 다 썼다고 표시합니다. 그때부터 오늘 복습의 노트 쓰기 항목에서 빠집니다")
                }
                // An icon like the bar's other items; the syntax in use is checked in the menu and named in the tooltip.
                Menu {
                    Picker("수식 문법", selection: $meta.math) {
                        ForEach(MathSyntax.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("수식 " + meta.math.label, systemImage: "function")
                }
                .help("수식 문법: \(meta.math.label). 이 노트의 $…$ 수식을 어떤 문법으로 읽을지")
                linkMenu
                if mode != .read {
                    Button { showsAssets.toggle() } label: {
                        Label("애셋", systemImage: "photo.on.rectangle").foregroundStyle(showsAssets ? accent.color : Theme.Palette.textSecondary)
                    }
                    .help("assets 폴더의 파일을 끌어서 본문에 넣습니다. 이미지는 본문에 바로 끌어 놓거나 붙여 넣어도 됩니다")
                }
            }
            if mode != .read && showsAssets {
                AssetTray(store: store, link: { AssetTray.markdown(for: $0, path: store.link(to: "assets/" + $0.lastPathComponent, from: note)) },
                          insert: { pendingInsert = $0 }, revision: assetsRevision)
                    .transition(.move(edge: .top).combined(with: .opacity))
                Theme.Palette.lineSoft.frame(height: 1)
            }
            if mode == .read {
                HTMLView(body: HTMLRenderer.render(ParsedNote(frontmatter.render(body: body_))), baseURL: note.url.deletingLastPathComponent(),
                         mathSyntax: meta.math.rawValue, openNote: openNote)
            } else {
                MarkdownEditor(text: $body_, baseURL: note.url.deletingLastPathComponent(), math: meta.math, live: mode == .live,
                               insert: $pendingInsert, saveFile: saveFile, openNote: openNote)
            }
        }
        .background(Theme.Palette.card)
        .animation(.snappy(duration: 0.25), value: showsAssets)
        // Edits save on their own; ⌘S is kept only for the habit, with no button of its own.
        .background { Button("") { save(force: false) }.keyboardShortcut("s").opacity(0).allowsHitTesting(false).accessibilityHidden(true) }
        .onAppear(perform: load)
        // Saved a moment after typing stops, and whenever the note goes away: switching notes or courses, closing the
        // window or quitting would otherwise drop the edits.
        .task(id: body_) {
            guard dirty else { return }
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { save(force: false) }
        }
        .onChange(of: meta.math) { if dirty { save(force: false) } }
        .onChange(of: scenePhase) { _, phase in if phase != .active, dirty { save(force: false) } }
        .onDisappear { if dirty { save(force: false) } }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in if dirty { save(force: false) } }
        #endif
        .alert("다른 곳에서 바뀐 노트입니다", isPresented: $conflict) {
            Button("내 것으로 덮어쓰기", role: .destructive) { save(force: true) }
            Button("다시 읽기") { load() }
            Button("나중에", role: .cancel) {}
        } message: {
            Text("다른 기기나 프로그램이 이 노트를 고쳤습니다. 다시 읽으면 여기서 고친 내용은 사라집니다.")
        }
        .onChange(of: insert.wrappedValue) { _, text in
            guard let text else { return }
            body_ += (body_.hasSuffix("\n") ? "\n" : "\n\n") + text + "\n"
            insert.wrappedValue = nil
        }
    }

    var linkMenu: some View {
        let file = workspace.course(courseId)?.file
        let sessions = (file?.sessions ?? []).filter { !$0.isCancelled && $0.date <= .now }.sorted { $0.date > $1.date }
        let exams = (file?.exams ?? []).sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
        // Outline order: `order` counts among siblings only, so sorting by it alone interleaves chapters and their units.
        let outline = UnitTree.outline(file?.units ?? [])
        let units = outline.map(\.unit)
        // The session's pointer, not the frontmatter, is what the sessions page reads.
        let session = file?.sessions.first { meta.id != nil && ($0.roughNoteId == meta.id || $0.reviewNoteId == meta.id) }
        let current: String = switch meta.kind {
        case .rough, .review: session.map { "\(file?.name(of: $0) ?? "") \(meta.kind.label) 노트" } ?? "\(meta.kind.label) 노트 · 회차 없음"
        case .examSummary: exams.first { $0.id == meta.examId }.map { "\($0.title) 시험 종합 정리" } ?? "시험 종합 정리 · 시험 없음"
        case .topic: "단원 정리 · " + (units.filter { meta.unitIds.contains($0.id) }.map(\.title).joined(separator: ", ").nilIfEmpty ?? "단원 없음")
        case .free: "자유 노트"
        }
        func item(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
            Button(action: action) { if on { Label(title, systemImage: "checkmark") } else { Text(title) } }
        }
        return Menu {
            ForEach([NoteKind.rough, .review], id: \.self) { kind in
                Menu("\(kind.label) 노트로") {
                    ForEach(sessions) { s in
                        item(file?.name(of: s) ?? "", on: meta.kind == kind && session?.id == s.id) { relink(kind, session: s.id) }
                    }
                }
            }
            Menu("시험 종합 정리로") {
                ForEach(exams) { e in item(e.title, on: meta.kind == .examSummary && meta.examId == e.id) { relink(.examSummary, exam: e.id) } }
            }
            Menu("단원 정리로") {
                ForEach(outline, id: \.unit.id) { u, depth in
                    item(String(repeating: "   ", count: depth) + u.title, on: meta.kind == .topic && meta.unitIds.contains(u.id)) { toggleTopic(u.id) }
                }
            }
            item("자유 노트로", on: meta.kind == .free) { relink(.free) }
        } label: {
            Label(current, systemImage: "link")
        }
        .help("노트 종류와 연결: \(current)")
    }

    /// One kind at a time: becoming another kind lets go of the session or exam the old one belonged to.
    func relink(_ kind: NoteKind, session: UUID? = nil, exam: UUID? = nil) {
        guard meta.id != nil else { return }
        meta.kind = kind
        meta.sessionId = session
        meta.examId = exam
        saveLinks()
    }

    func toggleTopic(_ unit: UUID) {
        if meta.kind != .topic { relink(.topic) }
        if let i = meta.unitIds.firstIndex(of: unit) { meta.unitIds.remove(at: i) } else { meta.unitIds.append(unit) }
        saveLinks()
    }

    // The body is saved first, so the link action rewrites the frontmatter of the text on screen; reading the file back
    // afterwards keeps the editor's next save from taking that write for someone else's.
    func saveLinks() {
        save(force: false)
        guard !conflict, let id = meta.id else { return }
        workspace.run(NoteLink(course: courseId, note: id, kind: meta.kind, session: meta.sessionId, exam: meta.examId, units: meta.unitIds))
        onDisk = (try? store.read(note)) ?? onDisk
        workspace.notesRevision += 1
    }

    func saveFile(_ name: String, _ data: Data) -> String? {
        var link: String?
        workspace.perform {
            let path = try store.addNoteAsset(named: name, data: data)
            link = AssetTray.markdown(for: URL(fileURLWithPath: path), path: store.link(to: path, from: note))
            assetsRevision += 1
        }
        return link
    }

    func load() {
        onDisk = (try? store.read(note)) ?? ""
        (frontmatter, body_) = Frontmatter.split(onDisk)
        saved = body_
        meta = note.meta
        savedMath = meta.math
    }

    func save(force: Bool) {
        guard !conflict || force else { return }
        guard let path = store.coursePath(of: note.url) else { return }
        var fm = frontmatter
        meta.apply(to: &fm)
        let text = fm.render(body: body_)
        do {
            try workspace.runThrowing(NoteWrite(course: courseId, note: path, text: text, expected: force ? nil : onDisk))
            onDisk = text
            saved = body_
            savedMath = meta.math
        } catch ActionError.conflict {
            conflict = true
        } catch {
            workspace.error = "\(error)"
        }
    }
}

extension MathSyntax {
    var label: String {
        switch self {
        case .latex: "LaTeX"
        case .asciimath: "AsciiMath"
        }
    }
}

extension NoteKind {
    var label: String {
        switch self {
        case .rough: "러프"
        case .review: "복습"
        case .examSummary: "시험 종합 정리"
        case .topic: "단원 정리"
        case .free: "자유"
        }
    }
}

