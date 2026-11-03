import FolioDomain
import FolioStorage
import SwiftUI

struct NoteList: View {
    @State private var model: NoteListModel
    @Environment(\.accent) private var accent
    @Binding var selection: UUID?

    init(workspace: Workspace, course: LoadedCourse, selection: Binding<UUID?>) {
        _model = State(initialValue: NoteListModel(workspace: workspace, course: course))
        _selection = selection
    }

    var body: some View {
        let shown = model.shown
        let parts = model.parts
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            HStack {
                Caption(String(localized: .notesCount(shown.count)))
                Spacer()
                ChoiceMenu(selection: $model.filter, options: model.filterOptions)
                Button { model.adding = true } label: { Image(systemName: "plus") }
                    .buttonStyle(.ghost)
                    .help(model.addHelp)
            }
            .padding(.horizontal, Theme.Space.s)
            .padding(.bottom, Theme.Space.xs)
            if shown.isEmpty {
                Text(model.emptyLine)
                    .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                    .padding(Theme.Inset.listRow)
            }
            ForEach(parts) { part in
                // One kind chosen in the filter is one section; its heading would only repeat the filter.
                if parts.count > 1 {
                    Caption(String(localized: .notesSection(part.title, part.rows.count)))
                        .padding(.horizontal, Theme.Space.s).padding(.top, Theme.Space.m).padding(.bottom, Theme.Space.xxs)
                }
                ForEach(part.rows) { row($0) }
            }
        }
        // The filter's kind is the likely one: a + under 단원 정리 makes a topic note.
        .sheet(isPresented: $model.adding) {
            NewNoteSheet(workspace: model.workspace, course: model.course, kind: model.filter ?? .free) { id in
                model.reload()
                selection = id
            }
        }
        .confirmationDialog(String(localized: .notesDeleteConfirm(model.deleting?.title ?? "")),
                            isPresented: Binding(get: { model.deleting != nil }, set: { if !$0 { model.deleting = nil } })) {
            Button(.notesTrash, role: .destructive) {
                guard let note = model.deleting else { return }
                model.delete(note)
                if note.meta.id != nil && note.meta.id == selection { selection = nil }
            }
        } message: {
            Text(.notesDeleteMessage)
        }
        // Notes made elsewhere (the Claude panel) and links changed in the editor show up here too.
        .onChange(of: selection) { _, id in model.reloadIfMissing(id) }
        .onChange(of: model.workspace.notesRevision) { model.reload() }
        .task(id: model.course.id) {
            model.reload()
            #if DEBUG && os(macOS)
            if SnapshotDriver.directory != nil, selection == nil { selection = model.parts.first?.rows.first?.note.meta.id }
            #endif
        }
    }

    func row(_ row: NoteListModel.Row) -> some View {
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
            Button(.notesOpen) { open(note) }
            Divider()
            Button(.notesDeleteEllipsis, systemImage: "trash", role: .destructive) { model.deleting = note }
        }
    }

    func open(_ note: NoteFile) {
        if let id = model.open(note) { selection = id }
    }
}

struct NotesView: View {
    @State private var model: NotesModel
    let selection: UUID?
    var insert: Binding<String?> = .constant(nil)
    let open: (UUID) -> Void

    init(workspace: Workspace, course: LoadedCourse, selection: UUID?, insert: Binding<String?> = .constant(nil), open: @escaping (UUID) -> Void) {
        _model = State(initialValue: NotesModel(workspace: workspace, course: course))
        self.selection = selection
        self.insert = insert
        self.open = open
    }

    var body: some View {
        if let note = model.note(selection) {
            if note.format == .tex {
                TextFileView(workspace: model.workspace, course: model.course, note: note).id(note.url)
            } else {
                NoteEditor(workspace: model.workspace, course: model.course, note: note, insert: insert) { title in
                    if let id = model.noteId(titled: title) { open(id) }
                }
                .id(note.url)
            }
        } else {
            ContentUnavailableView(String(localized: .notesChoose), systemImage: "doc.text", description: Text(.notesChooseDetail))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.Palette.page)
        }
    }
}

struct NoteEditor: View {
    enum Mode: Hashable { case read, write }
    /// From here the note panel holds the source and the preview side by side.
    nonisolated static let sideBySide: CGFloat = 880

    @State private var model: NoteEditorModel
    @Environment(\.accent) private var accent
    @Environment(\.scenePhase) private var scenePhase
    var insert: Binding<String?> = .constant(nil)
    let openNote: (String) -> Void
    @State private var mode = Mode.write
    @State private var wide = false
    @State private var preview = PreviewLink()
    @State private var showsAssets = false

    init(workspace: Workspace, course: LoadedCourse, note: NoteFile, insert: Binding<String?> = .constant(nil), openNote: @escaping (String) -> Void) {
        _model = State(initialValue: NoteEditorModel(workspace: workspace, course: course, note: note))
        self.insert = insert
        self.openNote = openNote
    }

    var body: some View {
        VStack(spacing: 0) {
            PageBar {
                if !wide {
                    Segmented(selection: $mode, options: [(.read, String(localized: .notesModeRead)), (.write, String(localized: .notesModeWrite))],
                              compact: true)
                    .help(Text(.notesModeToggle))
                }
            } trailing: {
                if let session = model.unfinishedReview {
                    Button { model.finishReview(session) } label: {
                        Label(.notesReviewDone, systemImage: "checkmark.circle").labelStyle(.titleAndIcon).padding(.horizontal, Theme.Space.s)
                    }
                    .help(Text(.notesReviewDoneHelp))
                }
                // An icon like the bar's other items; the syntax in use is checked in the menu and named in the tooltip.
                Menu {
                    Picker(String(localized: .notesMathSyntax), selection: $model.meta.math) {
                        ForEach(MathSyntax.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(String(localized: .notesMathLabel(model.meta.math.label)), systemImage: "function")
                }
                .help(Text(.notesMathHelp(model.meta.math.label)))
                NoteLinkMenu(model: model)
                if writing {
                    Button { showsAssets.toggle() } label: {
                        Label(.notesAssets, systemImage: "photo.on.rectangle").foregroundStyle(showsAssets ? accent.color : Theme.Palette.textSecondary)
                    }
                    .help(Text(.notesAssetsHelp))
                }
            }
            if writing && showsAssets {
                AssetTray(model: model)
                    .transition(.move(edge: .top).combined(with: .opacity))
                Theme.Palette.lineSoft.frame(height: 1)
            }
            if wide {
                HStack(spacing: 0) {
                    editor
                    Theme.Palette.lineSoft.frame(width: 1)
                    NoteReader(text: model.body, baseURL: model.baseURL, math: model.meta.math, openNote: openNote, edit: model.replaceLines, link: preview)
                }
            } else if mode == .read {
                NoteReader(text: model.body, baseURL: model.baseURL, math: model.meta.math, openNote: openNote, edit: model.replaceLines,
                           toggleMode: toggleMode)
            } else {
                editor
            }
        }
        .onGeometryChange(for: Bool.self) { $0.size.width >= Self.sideBySide } action: { wide = $0 }
        .background(Theme.Palette.card)
        .animation(.snappy(duration: 0.25), value: showsAssets)
        // Edits save on their own; ⌘S is kept only for the habit, with no button of its own.
        .background { Button("") { model.saveNow(force: false) }.keyboardShortcut("s").opacity(0).allowsHitTesting(false).accessibilityHidden(true) }
        .background {
            Button("", action: toggleMode).keyboardShortcut("e").disabled(wide)
                .opacity(0).allowsHitTesting(false).accessibilityHidden(true)
        }
        .onAppear(perform: model.load)
        // Saved a moment after typing stops, and whenever the note goes away: switching notes or courses, closing the
        // window or quitting would otherwise drop the edits.
        .task(id: model.body) {
            guard model.dirty else { return }
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { model.saveNow(force: false) }
        }
        .onChange(of: model.meta.math) { model.saveMath() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.saveIfDirty() } }
        .onDisappear { model.saveIfDirty() }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.saveIfDirty() }
        #endif
        .alert(String(localized: .notesConflict), isPresented: $model.conflict) {
            Button(.notesConflictOverwrite, role: .destructive) { model.saveNow(force: true) }
            Button(.notesConflictReload) { model.load() }
            Button(.notesConflictLater, role: .cancel) {}
        } message: {
            Text(.notesConflictMessage)
        }
        .onChange(of: insert.wrappedValue) { _, text in
            guard let text else { return }
            model.append(text)
            insert.wrappedValue = nil
        }
    }

    var writing: Bool { wide || mode == .write }

    func toggleMode() { mode = mode == .read ? .write : .read }

    var editor: some View {
        MarkdownEditor(text: $model.body, baseURL: model.baseURL, math: model.meta.math, insert: $model.pendingInsert,
                       saveFile: model.saveFile, openNote: openNote, onScroll: preview.follow)
    }
}

/// The note's kind and what it belongs to, one kind at a time. Shared by the markdown editor and a `.tex` note's view.
struct NoteLinkMenu: View {
    let model: NoteEditorModel

    var body: some View {
        let meta = model.meta
        let session = model.linkedSession
        let current = model.currentLink
        func item(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
            Button(action: action) { if on { Label(title, systemImage: "checkmark") } else { Text(title) } }
        }
        return Menu {
            ForEach([NoteKind.rough, .review], id: \.self) { kind in
                Menu(String(localized: .notesLinkAsKind(kind.label))) {
                    ForEach(model.linkSessions) { s in
                        item(model.sessionName(s), on: meta.kind == kind && session?.id == s.id) { model.relink(kind, session: s.id) }
                    }
                }
            }
            Menu(String(localized: .notesLinkAsExam)) {
                ForEach(model.linkExams) { e in item(e.title, on: meta.kind == .examSummary && meta.examId == e.id) { model.relink(.examSummary, exam: e.id) } }
            }
            Menu(String(localized: .notesLinkAsTopic)) {
                ForEach(model.outline, id: \.unit.id) { u, depth in
                    item(String(repeating: "   ", count: depth) + u.title, on: meta.kind == .topic && meta.unitIds.contains(u.id)) { model.toggleTopic(u.id) }
                }
            }
            item(String(localized: .notesLinkAsFree), on: meta.kind == .free) { model.relink(.free) }
        } label: {
            Label(current, systemImage: "link")
        }
        .help(Text(.notesLinkHelp(current)))
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
        case .rough: String(localized: .notesKindRough)
        case .review: String(localized: .notesKindReview)
        case .examSummary: String(localized: .notesKindExamSummary)
        case .topic: String(localized: .notesKindTopic)
        case .free: String(localized: .notesKindFree)
        }
    }
}
