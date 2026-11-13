import FolioDomain
import FolioStorage
import PDFKit
import SwiftUI

struct TextFileView: View {
    @State private var model: TextFileModel
    @State private var panes = NotePanes()
    @State private var wide = false
    // 0부터 센 쪽이다.
    @Binding private var requestedPage: Int?
    @Binding private var shownPage: Int?
    @State private var links: NoteEditorModel?
    @State private var controller: PDFController?
    @State private var renaming = false
    private var moves: MoveUndo?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    init(
        workspace: Workspace, course: LoadedCourse, material: UUID, requestedPage: Binding<Int?> = .constant(nil),
        shownPage: Binding<Int?> = .constant(nil)
    ) {
        _model = State(initialValue: TextFileModel(workspace: workspace, course: course, material: material))
        _requestedPage = requestedPage
        _shownPage = shownPage
    }

    init(workspace: Workspace, course: LoadedCourse, note: NoteFile, moves: MoveUndo? = nil) {
        self.moves = moves
        _model = State(initialValue: TextFileModel(workspace: workspace, course: course, source: .note(note)))
        _links = State(initialValue: NoteEditorModel(workspace: workspace, course: course, note: note))
        _requestedPage = .constant(nil)
        _shownPage = .constant(nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            bar
            // 열만 나타났다 사라지는 행 하나로 두어야 보기를 바꿀 때 편집기의 캐럿과 PDF의 쪽이 유지된다.
            HStack(spacing: 0) {
                if !model.isTex || shown != .read { source }
                if model.isTex && shown == .split { Theme.Palette.lineSoft.frame(width: 1) }
                if model.isTex && shown != .write { pdf }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: Bool.self) {
            $0.size.width >= NotePanes.sideBySide
        } action: {
            wide = $0
        }
        .background(Theme.Palette.card)
        // 파일을 곧 옮기므로 먼저 저장한다.
        .crumb(
            model.name, level: 2, symbol: model.isTex ? "doc.text" : "chevron.left.forwardslash.chevron.right",
            rename: links.map { _ in
                {
                    model.saveIfDirty()
                    renaming = true
                }
            }
        )
        .sheet(isPresented: $renaming) {
            if let links { NoteEditSheet(workspace: links.workspace, course: links.course, note: links.note, moves: moves) }
        }
        .onAppear(perform: model.load)
        .rememberingPanes($panes, id: model.isTex ? model.paneId : nil)
        .onChange(of: controller?.page) { _, page in if let page { shownPage = page } }
        #if DEBUG && os(macOS)
        .onChange(of: SnapshotDriver.shared.texMode) { _, mode in if let mode { panes.choose(mode) } }
        #endif
        .onChange(of: requestedPage) { _, page in
            guard page != nil, let controller, let page = takeRequestedPage() else { return }
            showPDF()
            controller.go(to: page)
        }
        .task(id: model.text) {
            guard model.dirty else { return }
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { model.saveNow(force: false) }
        }
        .task(id: "\(model.pdfRevision) \(model.pdfURL?.path ?? "")") { openPDF() }
        .onChange(of: model.outsideRevision) {
            model.refresh()
            links?.reloadMeta()
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.saveIfDirty() } }
        #if os(macOS)
        .onChange(of: colorScheme) { _, scheme in controller?.darken(scheme == .dark) }
        #endif
        .onDisappear { model.saveIfDirty() }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.saveIfDirty() }
        #endif
        .background {
            Button("") { model.saveNow(force: false) }.keyboardShortcut("s").opacity(0).allowsHitTesting(false).accessibilityHidden(true)
        }
        .alert(String(localized: .textFileConflict), isPresented: $model.conflict) {
            Button(.notesConflictOverwrite, role: .destructive) { model.saveNow(force: true) }
            Button(.notesConflictReload) { model.load() }
            Button(.notesConflictLater, role: .cancel) {}
        } message: {
            Text(.textFileConflictMessage)
        }
        .alert(String(localized: .textFileReplace(model.pdfName)), isPresented: $model.asksToReplace) {
            Button(.textFileReplaceConfirm, role: .destructive) { model.replace() }
            Button(.commonCancel, role: .cancel) {}
        } message: {
            Text(.textFileReplaceMessage)
        }
    }

    var source: some View {
        VStack(spacing: 0) {
            if model.unreadable {
                ContentUnavailableView(
                    String(localized: .fileViewCannotRead), systemImage: "doc.questionmark",
                    description: Text(.textFileUnreadable)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                SourceFileEditor(text: $model.text, language: model.format.highlightLanguage, reveal: $model.reveal)
            }
            if !model.issues.isEmpty { issueList }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder var pdf: some View {
        if let controller {
            // `PDFKitView`는 처음 받은 뷰를 계속 쓰므로, 빌드마다 controller에 뷰를 따로 준다.
            PDFKitView(controller: controller).id(ObjectIdentifier(controller)).frame(maxWidth: .infinity)
                #if os(macOS)
            .help(Text(.textFilePdfHelp))
                #endif
        } else if model.building {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView {
                Label(String(localized: .textFileNoPdf), systemImage: "doc.richtext")
            } description: {
                #if os(macOS)
                Text(model.errors.isEmpty ? .textFileNoPdfBuild : .textFileNoPdfErrors)
                #else
                Text(model.errors.isEmpty ? .textFileNoPdfBuildPad : .textFileNoPdfErrors)
                #endif
            } actions: {
                Button(.textFileBuild) { Task { await model.build() } }
                    .buttonStyle(.prominent)
                    .disabled(!model.canBuild)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    var shown: NotePanes.Mode { panes.shown(wide: wide) }

    func showPDF() {
        if shown == .write { panes.choose(wide ? .split : .read) }
    }

    var bar: some View {
        PageBar {
            if model.isTex { NotePanesPicker(panes: $panes, wide: wide) }
            if model.isTex {
                Button(.textFileBuild, systemImage: "hammer") { Task { await model.build() } }
                    #if os(macOS)
                .help(Text(.textFileBuildHelp))
                    #endif
                    .keyboardShortcut("b")
                    .disabled(!model.canBuild)
                if model.building {
                    ProgressView().controlSize(.small).padding(.horizontal, Theme.Space.xs)
                } else if !model.errors.isEmpty {
                    Text(.textFileErrorCount(model.errors.count)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.danger)
                }
            }
        } trailing: {
            if let links { NoteLinkMenu(model: links) }
            #if os(macOS)
            Button(.materialsOpenWithDefault, systemImage: "arrow.up.forward.app") { NSWorkspace.shared.open(model.fileURL) }
                .help(Text(.materialsOpenWithDefault))
            #endif
            if case .material(let id) = model.source {
                PageMenuButton(inBar: true) { MaterialMenu(courseId: model.course.id, materialId: id, host: .own) }
            } else if let links {
                PageMenuButton(inBar: true) {
                    NoteMenu(
                        courseId: links.course.id, note: links.note, host: .own, moves: moves, build: texBuild, canBuild: model.canBuild,
                        save: model.saveIfDirty)
                }
            }
        }
    }

    var texBuild: (@MainActor () -> Void)? {
        guard model.isTex else { return nil }
        let build: @MainActor () -> Void = { Task { await model.build() } }
        return build
    }

    var issueList: some View {
        VStack(spacing: 0) {
            Theme.Palette.lineSoft.frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(model.shownIssues.enumerated()), id: \.offset) { _, issue in
                        Button {
                            model.jump(to: issue)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                                Image(systemName: issue.severity == .error ? "xmark.octagon" : "exclamationmark.triangle")
                                    .foregroundStyle(issue.severity == .error ? Theme.Palette.danger : Theme.Palette.warning)
                                Text(model.label(issue)).font(Theme.Typeface.mono).foregroundStyle(Theme.Palette.text)
                                    .multilineTextAlignment(.leading).textSelection(.enabled)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, Theme.Space.l)
                            .padding(.vertical, Theme.Space.xs)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.pointing(.plain))
                        .disabled(!model.isHere(issue))
                    }
                }
                .padding(.vertical, Theme.Space.xs)
            }
            .overflowFade(.vertical)
            .frame(maxHeight: 160)
        }
    }

    func openPDF() {
        guard model.isTex, let url = model.pdfURL, let document = PDFDocument(url: url) else {
            controller = nil
            return
        }
        let requested = takeRequestedPage()
        // `rememberingPanes`가 기억한 보기를 되돌린 뒤에 해야 한다. 그 작업은 appear에서 이 task보다 먼저 돈다.
        if requested != nil { showPDF() }
        controller = PDFController(document: document, page: requested ?? controller?.page ?? 0)
        #if os(macOS)
        controller?.darken(colorScheme == .dark)
        controller?.onCommandClick { [model] page, point in model.showSource(page: page, at: point) }
        #endif
        controller?.restore()
    }

    func takeRequestedPage() -> Int? {
        defer { requestedPage = nil }
        return requestedPage
    }
}
