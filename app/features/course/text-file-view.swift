import FolioDomain
import FolioStorage
import PDFKit
import SwiftUI

/// A `.tex`, code or text file of the course, edited in place. A `.tex` is shown as a markdown note is: its source, its
/// PDF (built with ⌘B) beside it, or the PDF alone, by the same switch.
struct TextFileView: View {
    @State private var model: TextFileModel
    @State private var panes = NotePanes()
    @State private var wide = false
    /// A page a link asked for, 0-based, in the built PDF; taken once the PDF has it.
    @Binding private var requestedPage: Int?
    /// The built PDF's page, for the window's link to this `.tex`, as `FileView` reports a PDF's.
    @Binding private var shownPage: Int?
    /// A note's kind and links, for the same menu the markdown editor has.
    @State private var links: NoteEditorModel?
    @State private var controller: PDFController?
    @State private var renaming = false
    private var moves: MoveUndo?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    init(workspace: Workspace, course: LoadedCourse, material: UUID, requestedPage: Binding<Int?> = .constant(nil),
         shownPage: Binding<Int?> = .constant(nil)) {
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
            // The iPad's engine ships with the app, so there is nothing to install.
            #if os(macOS)
            if model.isTex, model.engineMissing { installHint }
            #endif
            // One row whose columns come and go, so switching keeps the editor's caret and the PDF's page.
            HStack(spacing: 0) {
                if !model.isTex || shown != .read { source }
                if model.isTex && shown == .split { Theme.Palette.lineSoft.frame(width: 1) }
                if model.isTex && shown != .write { pdf }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: Bool.self) { $0.size.width >= NotePanes.sideBySide } action: { wide = $0 }
        .background(Theme.Palette.card)
        // A `.tex` note renames from its name as a markdown note does; saved first, since the file is about to move.
        .crumb(model.name, level: 2, symbol: model.isTex ? "doc.text" : "chevron.left.forwardslash.chevron.right", rename: links.map { _ in {
            model.saveIfDirty()
            renaming = true
        } })
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
        // Saved a moment after typing stops, and whenever the file goes away, as notes are.
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
        // Edits save on their own; ⌘S is kept only for the habit, with no button of its own.
        .background { Button("") { model.saveNow(force: false) }.keyboardShortcut("s").opacity(0).allowsHitTesting(false).accessibilityHidden(true) }
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
                ContentUnavailableView(String(localized: .fileViewCannotRead), systemImage: "doc.questionmark",
                                       description: Text(.textFileUnreadable))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                SourceFileEditor(text: $model.text, language: model.format.highlightLanguage, reveal: $model.reveal)
            }
            if !model.issues.isEmpty { issueList }
        }
        .frame(maxWidth: .infinity)
    }

    /// The built PDF, or, before the first build, the build's state where the PDF will be.
    @ViewBuilder var pdf: some View {
        if let controller {
            // `PDFKitView` keeps the view it was made with, so each build's controller needs a view of its own.
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
                Text(model.engineMissing ? .textFileNoPdfEngine : model.errors.isEmpty ? .textFileNoPdfBuild : .textFileNoPdfErrors)
                #else
                // An iPad build made without the engine (`mise run tex-engine`) can still show the Mac's PDF.
                Text(model.engineMissing ? .textFileNoPdfMac : model.errors.isEmpty ? .textFileNoPdfBuildPad : .textFileNoPdfErrors)
                #endif
            } actions: {
                if !model.engineMissing || isMac {
                    Button(.textFileBuild) { Task { await model.build() } }
                        .buttonStyle(.prominent)
                        .disabled(!model.canBuild)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    var shown: NotePanes.Mode { panes.shown(wide: wide) }

    /// The Mac keeps its build button without Tectonic, beside the hint to install it; the iPad has nothing to install.
    private var isMac: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    /// A link to a page of this `.tex` is a page of its PDF, so the PDF comes into view if the source alone was.
    func showPDF() {
        if shown == .write { panes.choose(wide ? .split : .read) }
    }

    var bar: some View {
        PageBar {
            if model.isTex { NotePanesPicker(panes: $panes, wide: wide) }
            if model.isTex, !model.engineMissing || isMac {
                Button(.textFileBuild, systemImage: "hammer") { Task { await model.build() } }
                    .help(Text(.textFileBuildHelp))
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
                    NoteMenu(courseId: links.course.id, note: links.note, host: .own, moves: moves, build: texBuild, canBuild: model.canBuild,
                             save: model.saveIfDirty)
                }
            }
        }
    }

    /// iPadOS can't run Tectonic, so its menu has no build row either.
    var texBuild: (@MainActor () -> Void)? {
        #if os(macOS)
        guard model.isTex else { return nil }
        let build: @MainActor () -> Void = { Task { await model.build() } }
        return build
        #else
        nil
        #endif
    }

    var installHint: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.Palette.warning)
            Text(.textFileInstallHint).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary).textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.s)
        .overlay(alignment: .bottom) { Theme.Palette.lineSoft.frame(height: 1) }
    }

    /// Errors first; a click on one in this file puts the caret on its line.
    var issueList: some View {
        VStack(spacing: 0) {
            Theme.Palette.lineSoft.frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(model.noticeLines, id: \.self) { line in
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                            Image(systemName: "info.circle").foregroundStyle(Theme.Palette.textSecondary)
                            Text(line).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, Theme.Space.l)
                        .padding(.vertical, Theme.Space.xs)
                    }
                    ForEach(Array(model.shownIssues.enumerated()), id: \.offset) { _, issue in
                        Button { model.jump(to: issue) } label: {
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

    /// Reopened after each build at the page that was showing, so checking a fix doesn't start over at page one.
    func openPDF() {
        guard model.isTex, let url = model.pdfURL, let document = PDFDocument(url: url) else {
            controller = nil
            return
        }
        let requested = takeRequestedPage()
        // After `rememberingPanes` has put back the remembered view, which runs on appear, before this task.
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
