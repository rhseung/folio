import FolioDomain
import FolioStorage
import PDFKit
import SwiftUI

/// A `.tex`, code or text file of the course, edited in place. A `.tex` shows its PDF beside it, built with ⌘B.
struct TextFileView: View {
    @State private var model: TextFileModel
    /// A note's kind and links, for the same menu the markdown editor has.
    @State private var links: NoteEditorModel?
    @State private var controller: PDFController?
    @State private var renaming = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    init(workspace: Workspace, course: LoadedCourse, material: UUID) {
        _model = State(initialValue: TextFileModel(workspace: workspace, course: course, material: material))
    }

    init(workspace: Workspace, course: LoadedCourse, note: NoteFile) {
        _model = State(initialValue: TextFileModel(workspace: workspace, course: course, source: .note(note)))
        _links = State(initialValue: NoteEditorModel(workspace: workspace, course: course, note: note))
    }

    var body: some View {
        VStack(spacing: 0) {
            bar
            // iPadOS can't run Tectonic, so it gets no build button and no advice to install it.
            #if os(macOS)
            if model.isTex, model.engineMissing { installHint }
            #endif
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    if model.unreadable {
                        ContentUnavailableView(String(localized: .materialsViewerCannotOpen), systemImage: "doc.questionmark",
                                               description: Text(.textFileUnreadable))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        SourceFileEditor(text: $model.text, language: model.format.highlightLanguage, reveal: $model.reveal)
                    }
                    if !model.issues.isEmpty { issueList }
                }
                .frame(maxWidth: .infinity)
                if model.isTex, let controller {
                    Theme.Palette.lineSoft.frame(width: 1)
                    // `PDFKitView` keeps the view it was made with, so each build's controller needs a view of its own.
                    PDFKitView(controller: controller).id(ObjectIdentifier(controller)).frame(maxWidth: .infinity)
                        #if os(macOS)
                        .help(Text(.textFilePdfHelp))
                        #endif
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.card)
        // A `.tex` note renames from its name as a markdown note does; saved first, since the file is about to move.
        .crumb(model.name, level: 2, symbol: model.isTex ? "doc.text" : "chevron.left.forwardslash.chevron.right", rename: links.map { _ in {
            model.saveIfDirty()
            renaming = true
        } })
        .sheet(isPresented: $renaming) {
            if let links { NoteRenameSheet(workspace: links.workspace, course: links.course, note: links.note) }
        }
        .onAppear(perform: model.load)
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

    var bar: some View {
        PageBar {
            #if os(macOS)
            if model.isTex {
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
            #endif
        } trailing: {
            if let links { NoteLinkMenu(model: links) }
            #if os(macOS)
            Button(.materialsOpenWithDefault, systemImage: "arrow.up.forward.app") { NSWorkspace.shared.open(model.fileURL) }
                .help(Text(.materialsOpenWithDefault))
            #endif
        }
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
            .frame(maxHeight: 160)
        }
    }

    /// Reopened after each build at the page that was showing, so checking a fix doesn't start over at page one.
    func openPDF() {
        guard model.isTex, let url = model.pdfURL, let document = PDFDocument(url: url) else {
            controller = nil
            return
        }
        controller = PDFController(document: document, page: controller?.page ?? 0)
        #if os(macOS)
        controller?.darken(colorScheme == .dark)
        controller?.onCommandClick { [model] page, point in model.showSource(page: page, at: point) }
        #endif
        controller?.restore()
    }
}
