import FolioDomain
import FolioStorage
import SwiftUI

struct NoteEditor: View {
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
    @AppStorage("noteOutline") private var outlineOn = true
    @State private var outlinePopover = false
    @State private var outlineFit = NoteOutlineFit(width: 0)
    @State private var outlineOwner = UUID()
    @Environment(\.paneFocused) private var paneFocused
    @Environment(CrumbTrail.self) private var trail: CrumbTrail?
    let moves: MoveUndo?

    init(
        workspace: Workspace, course: LoadedCourse, note: NoteFile, anchor: AppLink.Anchor? = nil,
        insert: Binding<String?> = .constant(nil),
        moves: MoveUndo? = nil
    ) {
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
                    Button {
                        model.finishReview(session)
                    } label: {
                        Label(.notesReviewDone, systemImage: "checkmark.circle").labelStyle(.titleAndIcon).padding(
                            .horizontal, Theme.Space.s)
                    }
                    .help(Text(.notesReviewDoneHelp))
                }
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
                    Button {
                        showsAssets.toggle()
                    } label: {
                        Label(.notesAssets, systemImage: "photo.on.rectangle").foregroundStyle(
                            showsAssets ? accent.color : Theme.Palette.textSecondary)
                    }
                    .help(Text(.notesAssetsHelp))
                    Button {
                        showInputGuide(model.meta.math)
                    } label: {
                        Label(.notesGuideTitle, systemImage: "keyboard")
                    }
                    .help(Text(.notesGuideTitle))
                }
                outlineButton
                PageMenuButton(inBar: true) {
                    NoteMenu(courseId: model.course.id, note: model.note, host: .own, moves: moves, save: model.saveIfDirty)
                }
            }
            if writing && showsAssets {
                AssetTray(model: model)
                    .transition(.move(edge: .top).combined(with: .opacity))
                Theme.Palette.lineSoft.frame(height: 1)
            }
            // 열만 나타났다 사라지는 행 하나로 두어야 보기를 바꿀 때 편집기의 캐럿과 미리보기의 스크롤이 유지된다.
            HStack(spacing: 0) {
                if shown != .read { editor }
                if shown == .split { Theme.Palette.lineSoft.frame(width: 1) }
                if shown != .write {
                    NotePreview(
                        text: model.body, baseURL: model.baseURL, math: model.meta.math, openNote: openNote, anchor: anchor,
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
        .onGeometryChange(for: Bool.self) {
            $0.size.width >= NotePanes.sideBySide
        } action: {
            wide = $0
        }
        .onGeometryChange(for: NoteOutlineFit.self) {
            NoteOutlineFit(width: $0.size.width)
        } action: {
            outlineFit = $0
        }
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
        .background {
            Button("") { model.saveNow(force: false) }.keyboardShortcut("s").opacity(0).allowsHitTesting(false).accessibilityHidden(true)
        }
        // 파일을 곧 옮기므로 먼저 저장한다.
        .crumb(
            model.note.title, level: 2, symbol: "doc.text",
            rename: {
                model.saveIfDirty()
                renaming = true
            }
        )
        .sheet(isPresented: $renaming) { NoteEditSheet(workspace: model.workspace, course: model.course, note: model.note, moves: moves) }
        .onAppear(perform: model.load)
        .rememberingPanes($panes, id: model.note.meta.id)
        // 타자가 멈춘 직후와 노트가 사라질 때 저장한다. 그러지 않으면 노트나 과목을 바꾸거나, 창을 닫거나, 앱을 끝낼 때
        // 편집이 사라진다.
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
    var outlineShown: Bool { outlineFit.docks(shown) ? outlineOn : outlinePopover }

    func toggleOutline() {
        if outlineFit.docks(shown) {
            withAnimation(Theme.Motion.standard) { outlineOn.toggle() }
        } else {
            outlinePopover.toggle()
        }
    }

    func registerOutline() {
        guard let trail else { return }
        guard paneFocused, !outline.isEmpty else { return trail.clearOutline(owner: outlineOwner) }
        trail.setOutline(OutlineCommand(shown: outlineShown, toggle: toggleOutline), owner: outlineOwner)
    }

    var outlineButton: some View {
        Button {
            toggleOutline()
        } label: {
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
        MarkdownEditor(
            text: $model.body, baseURL: model.baseURL, math: model.meta.math, insert: $model.pendingInsert,
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
