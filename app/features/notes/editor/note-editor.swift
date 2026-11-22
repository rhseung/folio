import FolioDomain
import FolioMarkdown
import FolioStorage
import SwiftUI

struct NoteEditor: View {
    @State private var model: NoteEditorModel
    @Environment(\.accent) private var accent
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.showInputGuide) private var showInputGuide
    @Environment(\.openLink) private var openLink
    @Environment(\.screenRequests) private var requests
    @Environment(\.itemSheets) private var sheets
    @Environment(\.noteCallouts) private var callouts
    var anchor: AppLink.Anchor?
    var insert: Binding<String?> = .constant(nil)
    @State private var panes = NotePanes()
    @State private var wide = false
    @State private var preview = PreviewLink()
    @State private var showsAssets = false
    @State private var tray: AssetTrayModel
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
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
        _tray = State(initialValue: AssetTrayModel(editor: model))
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
            if writing && showsAssets && !traySheet {
                AssetTray(model: tray)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
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
                        revision: model.notesRevision, views: outline.views,
                        makeCard: makeCard)
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
        .task {
            guard requests.contains(.outlinePopover) else { return }
            try? await Task.sleep(for: .seconds(0.5))
            if !outlineFit.docks(shown) { outlinePopover = true }
        }
        .background(Theme.Palette.card)
        .animation(Theme.Motion.standard, value: showsAssets)
        .sheet(isPresented: traySheetShown) {
            AssetTray(model: tray, inSheet: true)
                .presentationDetents([Self.trayLow, .large], selection: trayDetent)
                .presentationBackgroundInteraction(.enabled(upThrough: Self.trayLow))
                .presentationDragIndicator(.visible)
        }
        .background {
            Button("") { model.saveNow(force: false) }.keyboardShortcut("s").opacity(0).allowsHitTesting(false).accessibilityHidden(true)
        }
        .crumb(model.note.title, level: 2, symbol: "doc.text")
        .onAppear(perform: model.load)
        .rememberingPanes($panes, id: model.note.meta.id)
        // 타자가 멈춘 직후와 노트가 사라질 때 저장한다. 그러지 않으면 노트나 과목을 바꾸거나, 창을 닫거나, 앱을 끝낼 때
        // 편집이 사라진다.
        .task(id: model.body) {
            guard model.dirty else { return }
            try? await Task.sleep(for: SavePause.delay)
            if !Task.isCancelled { model.saveNow(force: false) }
        }
        .onChange(of: model.meta.math) { model.saveMath() }
        .onChange(of: requests.contains(.mathPalette)) { _, open in showsMath = open }
        .onChange(of: requests.viewMode, initial: true) { _, mode in if let mode { panes.choose(mode) } }
        .onChange(of: requests.assets, initial: true) { _, expanded in
            guard let expanded else { return }
            showsAssets = true
            tray.expanded = expanded
        }
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

    // iPhone에서는 서랍이 본문을 밀어내지 않게 시트로 띄운다. 낮은 높이에서는 뒤의 본문에 계속 쓸 수 있다.
    var traySheet: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }

    static let trayLow = PresentationDetent.height(Theme.Size.assetTray)

    var traySheetShown: Binding<Bool> {
        Binding {
            writing && showsAssets && traySheet
        } set: {
            if !$0 { showsAssets = false }
        }
    }

    var trayDetent: Binding<PresentationDetent> {
        Binding {
            tray.expanded ? .large : Self.trayLow
        } set: {
            tray.expanded = $0 == .large
        }
    }
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

    var makeCard: (@MainActor (Int) -> Void)? {
        guard model.meta.id != nil else { return nil }
        return { line in
            if let draft = model.cardDraft(at: line, callouts: callouts) { sheets.present(.card(course: model.course.id, draft: draft)) }
        }
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
            revision: model.notesRevision, insertMath: $model.pendingMath, insertBlock: $model.pendingBlock,
            openGuide: { showInputGuide(model.meta.math) },
            views: outline.views)
    }
}
