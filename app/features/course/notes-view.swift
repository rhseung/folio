import FolioDomain
import FolioStorage
import SwiftUI

struct NoteList: View {
    @State private var model: NoteListModel
    @Environment(\.accent) private var accent
    @Binding var selection: UUID?

    init(workspace: Workspace, course: LoadedCourse, selection: Binding<UUID?>, moves: MoveUndo) {
        _model = State(initialValue: NoteListModel(workspace: workspace, course: course, moves: moves))
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
            UndoMoveButton(moves: model.moves) { model.undoMove() }
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
        // The filter's kind is the likely one: a + under 단원 노트 makes a unit note.
        .sheet(isPresented: $model.adding) {
            NewNoteSheet(workspace: model.workspace, course: model.course, kind: model.filter ?? .free) { id in
                model.reload()
                selection = id
            }
        }
        .confirming($model.pending)
        // Notes made elsewhere (the Claude panel, a session's rough note) and links changed in the editor show up here too.
        .onChange(of: model.notesRevision) { model.reload() }
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
            NoteMenu(courseId: model.course.id, note: note, host: .list, moves: model.moves, open: { open(note) }, removed: {
                if note.meta.id != nil && note.meta.id == selection { selection = nil }
            })
        }
    }

    func open(_ note: NoteFile) {
        if let id = model.open(note) { selection = id }
    }
}

struct NotesView: View {
    @State private var model: NotesModel
    let selection: UUID?
    var anchor: AppLink.Anchor?
    var insert: Binding<String?> = .constant(nil)
    let moves: MoveUndo

    init(workspace: Workspace, course: LoadedCourse, selection: UUID?, anchor: AppLink.Anchor? = nil, insert: Binding<String?> = .constant(nil),
         moves: MoveUndo) {
        _model = State(initialValue: NotesModel(workspace: workspace, course: course))
        self.moves = moves
        self.selection = selection
        self.anchor = anchor
        self.insert = insert
    }

    var body: some View {
        if let note = model.note(selection) {
            if note.format == .tex {
                TextFileView(workspace: model.workspace, course: model.course, note: note, moves: moves).id(note.url)
            } else {
                NoteEditor(workspace: model.workspace, course: model.course, note: note, anchor: anchor, insert: insert, moves: moves)
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
    /// From here the note panel can hold the source and the preview side by side.
    @State private var model: NoteEditorModel
    @Environment(\.accent) private var accent
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.showInputGuide) private var showInputGuide
    @Environment(\.openLink) private var openLink
    var anchor: AppLink.Anchor?
    var insert: Binding<String?> = .constant(nil)
    @State private var panes = NotePanes()
    @State private var wide = false
    @State private var preview = PreviewLink()
    @State private var showsAssets = false
    @State private var renaming = false
    @State private var palette: MathPaletteModel
    @State private var showsMath = false
    @State private var outline = NoteOutlineModel()
    /// The outline beside the note stays shown or hidden for every note on this device.
    @AppStorage("noteOutline") private var outlineOn = true
    @State private var outlinePopover = false
    @State private var outlineFit = NoteOutlineFit(width: 0)
    @State private var outlineOwner = UUID()
    @Environment(\.paneFocused) private var paneFocused
    @Environment(CrumbTrail.self) private var trail: CrumbTrail?
    let moves: MoveUndo?

    init(workspace: Workspace, course: LoadedCourse, note: NoteFile, anchor: AppLink.Anchor? = nil, insert: Binding<String?> = .constant(nil),
         moves: MoveUndo? = nil) {
        let model = NoteEditorModel(workspace: workspace, course: course, note: note)
        _model = State(initialValue: model)
        _palette = State(initialValue: MathPaletteModel(editor: model))
        self.moves = moves
        self.anchor = anchor
        self.insert = insert
    }

    var body: some View {
        VStack(spacing: 0) {
            PageBar {
                NotePanesPicker(panes: $panes, wide: wide)
            } trailing: {
                if let session = model.unfinishedReview {
                    Button { model.finishReview(session) } label: {
                        Label(.notesReviewDone, systemImage: "checkmark.circle").labelStyle(.titleAndIcon).padding(.horizontal, Theme.Space.s)
                    }
                    .help(Text(.notesReviewDoneHelp))
                }
                // An icon like the bar's other items; the syntax in use is chosen on top of the palette and named in
                // the tooltip.
                Button {
                    palette.fence = writing ? outline.views.editor?.caretFence : nil
                    showsMath.toggle()
                } label: {
                    Label(String(localized: .notesMathLabel(model.meta.math.label)), systemImage: "function")
                }
                .help(Text(.notesMathHelp(model.meta.math.label)))
                .popover(isPresented: $showsMath, arrowEdge: .bottom) { MathPalette(model: palette, writing: writing) }
                NoteLinkMenu(model: model)
                if writing {
                    Button { showsAssets.toggle() } label: {
                        Label(.notesAssets, systemImage: "photo.on.rectangle").foregroundStyle(showsAssets ? accent.color : Theme.Palette.textSecondary)
                    }
                    .help(Text(.notesAssetsHelp))
                    // The way by touch; on the Mac also 도움말 › 입력 안내 (⌘/) and the `/` menu.
                    Button { showInputGuide(model.meta.math) } label: {
                        Label(.notesGuideTitle, systemImage: "keyboard")
                    }
                    .help(Text(.notesGuideTitle))
                }
                outlineButton
                PageMenuButton(inBar: true) { NoteMenu(courseId: model.course.id, note: model.note, host: .own, moves: moves, save: model.saveIfDirty) }
            }
            if writing && showsAssets {
                AssetTray(model: model)
                    .transition(.move(edge: .top).combined(with: .opacity))
                Theme.Palette.lineSoft.frame(height: 1)
            }
            // One row whose columns come and go, so switching keeps the editor's caret and the preview's scroll.
            HStack(spacing: 0) {
                if shown != .read { editor }
                if shown == .split { Theme.Palette.lineSoft.frame(width: 1) }
                if shown != .write {
                    NotePreview(text: model.body, baseURL: model.baseURL, math: model.meta.math, openNote: openNote, anchor: anchor,
                                noteLink: model.note.meta.id.map { AppLink(.note, $0) }, edit: model.replaceLines,
                                link: shown == .split ? preview : nil, toggleMode: toggleMode, embeds: model.embeds,
                                revision: model.notesRevision, views: outline.views)
                }
                if outlineDocked {
                    Theme.Palette.lineSoft.frame(width: 1)
                    NoteOutlineList(model: outline)
                        .frame(width: Theme.Size.noteOutline)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .onGeometryChange(for: Bool.self) { $0.size.width >= NotePanes.sideBySide } action: { wide = $0 }
        .onGeometryChange(for: NoteOutlineFit.self) { NoteOutlineFit(width: $0.size.width) } action: { outlineFit = $0 }
        .onChange(of: model.body, initial: true) { outline.read(model.body) }
        .onChange(of: [paneFocused, outlineShown, outline.isEmpty], initial: true) { registerOutline() }
        .onDisappear { trail?.clearOutline(owner: outlineOwner) }
        #if DEBUG && os(macOS)
        .task {
            guard SnapshotDriver.outline == "popover" else { return }
            try? await Task.sleep(for: .seconds(0.5))
            if !outlineFit.docks(shown) { outlinePopover = true }
        }
        #endif
        .background(Theme.Palette.card)
        .animation(Theme.Motion.standard, value: showsAssets)
        // Edits save on their own; ⌘S is kept only for the habit, with no button of its own.
        .background { Button("") { model.saveNow(force: false) }.keyboardShortcut("s").opacity(0).allowsHitTesting(false).accessibilityHidden(true) }
        // The note's name is the screen's title; clicking it renames the note. Saved first: the file is about to move.
        .crumb(model.note.title, level: 2, symbol: "doc.text", rename: {
            model.saveIfDirty()
            renaming = true
        })
        .sheet(isPresented: $renaming) { NoteEditSheet(workspace: model.workspace, course: model.course, note: model.note, moves: moves) }
        .onAppear(perform: model.load)
        .rememberingPanes($panes, id: model.note.meta.id)
        // Saved a moment after typing stops, and whenever the note goes away: switching notes or courses, closing the
        // window or quitting would otherwise drop the edits.
        .task(id: model.body) {
            guard model.dirty else { return }
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { model.saveNow(force: false) }
        }
        .onChange(of: model.meta.math) { model.saveMath() }
        #if DEBUG && os(macOS)
        .onChange(of: SnapshotDriver.shared.mathPaletteOpen) { _, open in showsMath = open }
        #endif
        .onChange(of: model.notesRevision) { model.refresh() }
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

    var shown: NotePanes.Mode { panes.shown(wide: wide) }
    var writing: Bool { shown != .read }

    var outlineDocked: Bool { outlineOn && !outline.isEmpty && outlineFit.docks(shown) }
    /// Beside the note, the remembered choice; where there's no room for it, the popover.
    var outlineShown: Bool { outlineFit.docks(shown) ? outlineOn : outlinePopover }

    func toggleOutline() {
        if outlineFit.docks(shown) {
            withAnimation(Theme.Motion.standard) { outlineOn.toggle() }
        } else {
            outlinePopover.toggle()
        }
    }

    /// While the pane is focused, the menu bar's 목차 command works on this note's outline.
    func registerOutline() {
        guard let trail else { return }
        guard paneFocused, !outline.isEmpty else { return trail.clearOutline(owner: outlineOwner) }
        trail.setOutline(OutlineCommand(shown: outlineShown, toggle: toggleOutline), owner: outlineOwner)
    }

    var outlineButton: some View {
        Button { toggleOutline() } label: {
            Label(.notesOutlineTitle, systemImage: "list.bullet.indent")
                .foregroundStyle(outlineShown ? accent.color : Theme.Palette.textSecondary)
        }
        .help(Text(outlineShown ? .notesOutlineHide : .notesOutlineShow))
        .disabled(outline.isEmpty)
        .popover(isPresented: $outlinePopover, arrowEdge: .bottom) {
            NoteOutlineList(model: outline) { outlinePopover = false }
                .frame(width: Theme.Size.noteOutlinePopover.width)
                .frame(maxHeight: Theme.Size.noteOutlinePopover.height)
        }
    }

    func toggleMode() { panes.toggle() }

    func openNote(_ title: String) {
        if let link = model.link(titled: title) { openLink(link, course: model.course.id) }
    }

    var editor: some View {
        MarkdownEditor(text: $model.body, baseURL: model.baseURL, math: model.meta.math, insert: $model.pendingInsert,
                       saveFile: model.saveFile, openNote: openNote,
                       onScroll: { [preview, outline] line, frac in
                           preview.follow(line: line, frac: frac)
                           outline.views.editorScrolled(line)
                       },
                       assist: model.assist, anchor: anchor, embeds: model.embeds,
                       revision: model.notesRevision, insertMath: $model.pendingMath,
                       openGuide: { showInputGuide(model.meta.math) },
                       views: outline.views)
    }
}

/// The note's kind and what it belongs to, one kind at a time. Shared by the markdown editor and a `.tex` note's view.
struct NoteLinkMenu: View {
    let model: NoteEditorModel

    var body: some View {
        let meta = model.meta
        let current = model.currentLink
        func item(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
            Button(action: action) { if on { Label(title, systemImage: "checkmark") } else { Text(title) } }
        }
        return Menu {
            ForEach([NoteKind.rough, .review], id: \.self) { kind in
                Menu(String(localized: .notesLinkAsKind(kind.label))) {
                    ForEach(model.linkSessions(kind)) { s in
                        item(model.sessionName(s), on: model.isLinked(s, as: kind)) { model.pick(s.id, as: kind) }
                    }
                }
            }
            Menu(String(localized: .notesLinkAsExam)) {
                ForEach(model.linkExams) { e in item(e.title, on: meta.kind == .examSummary && meta.examId == e.id) { model.relink(.examSummary, exam: e.id) } }
            }
            Menu(String(localized: .notesLinkAsUnit)) {
                ForEach(model.outline, id: \.unit.id) { u, depth in
                    item(String(repeating: "   ", count: depth) + u.title, on: meta.kind == .unit && meta.unitIds.contains(u.id)) { model.toggleUnit(u.id) }
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
        case .unit: String(localized: .notesKindUnit)
        case .free: String(localized: .notesKindFree)
        }
    }
}
