import FolioDomain
import FolioStorage
import SwiftUI

/// A file shown in the pane, by the renderer its format picks (`MaterialFormat.renderer`, #179). Every place that shows
/// a file goes through this: the materials page (and with it every `folio://material` link from assignments, problem
/// sets, exams, units and search), the review's sources, and a semester's `_Admin` files.
struct FileView: View {
    @State private var model: FileViewModel
    /// A page a link asked for, 0-based; taken once the PDF has it.
    @Binding private var requestedPage: Int?
    /// The 0-based page the PDF is on, for the window's link (`folio://material/<ID>#page=N`), so back, forward and a
    /// tab moved to its own window come back to it.
    @Binding private var shownPage: Int?
    @State private var thumbnails = true
    @State private var query = ""
    @Environment(\.askClaude) private var askClaude

    init(workspace: Workspace, course: LoadedCourse, material: UUID, requestedPage: Binding<Int?> = .constant(nil),
         shownPage: Binding<Int?> = .constant(nil), remembersPage: Bool = true) {
        _model = State(initialValue: FileViewModel(workspace: workspace, course: course, subject: .material(material), remembersPage: remembersPage))
        _requestedPage = requestedPage
        _shownPage = shownPage
    }

    init(workspace: Workspace, course: LoadedCourse, note: NoteFile) {
        _model = State(initialValue: FileViewModel(workspace: workspace, course: course, subject: .note(note)))
        _requestedPage = .constant(nil)
        _shownPage = .constant(nil)
    }

    /// A file no course tracks: shown only, never written.
    init(workspace: Workspace, url: URL) {
        _model = State(initialValue: FileViewModel(workspace: workspace, course: nil, subject: .file(url)))
        _requestedPage = .constant(nil)
        _shownPage = .constant(nil)
    }

    var body: some View {
        if model.editsInPlace, let course = model.course {
            // The editor brings its own bar, crumb and saving.
            switch model.subject {
            case .material(let id):
                TextFileView(workspace: model.workspace, course: course, material: id, requestedPage: $requestedPage, shownPage: $shownPage)
            case .note(let note): TextFileView(workspace: model.workspace, course: course, note: note)
            case .file: EmptyView()
            }
        } else {
            shown
        }
    }

    var shown: some View {
        VStack(spacing: 0) {
            if model.opensElsewhere || isPDF { bar }
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.card)
        .crumb(model.name, level: 2, symbol: model.symbol)
        .task(id: model.url) { await model.load(page: takeRequestedPage()) }
        // While a class is being recorded, the pages it goes through are kept with the recording.
        .onChange(of: pdf?.page) { _, page in
            guard let page else { return }
            model.showing(page)
            shownPage = page
        }
        // A page already open when recording starts doesn't change, so it is told then.
        .onChange(of: model.recording) { _, recording in if recording != nil, let page = pdf?.page { model.showing(page) } }
        // Another link to this file at another page, while it is open.
        .onChange(of: requestedPage) { _, page in
            if page != nil, let pdf, let page = takeRequestedPage() { pdf.go(to: page) }
        }
        .onDisappear { model.closed(at: pdf?.page) }
        // The progress sheet asked for this file's split screen before opening it.
        .onChange(of: pdf == nil, initial: true) { _, _ in takeSplitAsk() }
        .onChange(of: model.workspace.splitAsk) { _, _ in takeSplitAsk() }
        #if DEBUG && os(macOS)
        .onChange(of: SnapshotDriver.shared.askPage) { _, ask in
            if ask, let c = pdf, let item = model.pageContext(c.page, in: c) { askClaude?(item) }
        }
        #endif
    }

    @ViewBuilder var content: some View {
        switch model.loaded {
        case .loading:
            ProgressView()
        case .failed:
            ContentUnavailableView(String(localized: .fileViewCannotRead), systemImage: "doc.questionmark", description: Text(model.name))
        case .pdf(let controller):
            PDFContent(model: model, controller: controller, thumbnails: thumbnails)
        case .markdown(let text):
            NotePreview(text: text, baseURL: model.url.deletingLastPathComponent(), math: model.math, embeds: model.embeds,
                        revision: model.workspace.notesRevision)
        case .source(let text):
            SourceFileEditor(text: .constant(text), language: model.format.highlightLanguage, reveal: .constant(nil), editable: false)
        case .image(let url):
            ImagePane(url: url)
        case .audio(let url):
            AudioPane(url: url, name: model.name)
        case .quickLook(let url):
            QuickLookPane(url: url)
        case .unsupported:
            ContentUnavailableView {
                Label(String(localized: .fileViewCannotShow), systemImage: model.symbol)
            } description: {
                Text(.fileViewCannotShowDetail(model.url.pathExtension.uppercased()))
            } actions: {
                OpenElsewhereButton(url: model.url, prominent: true)
            }
        }
    }

    var pdf: PDFController? {
        if case .pdf(let controller) = model.loaded { controller } else { nil }
    }

    var isPDF: Bool { pdf != nil }

    /// Page and zoom lead; search and opening elsewhere trail, as in Preview. Where the pane is too narrow for every
    /// tool, zoom, split, link and Claude fold into one ⋯ menu; the thumbnails, the page count and the search stay out.
    var bar: some View {
        ViewThatFits(in: .horizontal) {
            barRow(folded: false)
            barRow(folded: true)
        }
        // Zoom's keys whichever row is shown: a folded menu's items don't take keys while it is closed, and the two
        // rows would otherwise claim the same keys twice.
        .background {
            if let c = pdf {
                Group {
                    Button("") { c.zoomOut() }.keyboardShortcut("-")
                    Button("") { c.fit() }.keyboardShortcut("0")
                    Button("") { c.zoomIn() }.keyboardShortcut("=")
                }
                .opacity(0).allowsHitTesting(false).accessibilityHidden(true)
            }
        }
    }

    func barRow(folded: Bool) -> some View {
        PageBar {
            if let c = pdf {
                if model.splitting == nil {
                    // Not `sidebar.leading`: the course column's button beside it is that glyph (#402).
                    Button(.materialsViewerThumbnails, systemImage: "sidebar.squares.left") { thumbnails.toggle() }.help(Text(.materialsViewerThumbnails))
                }
                // Its own width always: squeezed, the count broke a digit per line (#402).
                Text("\(c.page + 1) / \(c.pageCount)").monospacedDigit().foregroundStyle(Theme.Palette.textSecondary)
                    .fixedSize().padding(.horizontal, Theme.Space.xs)
                if !folded { zoomButtons(c) }
            }
        } trailing: {
            if let c = pdf {
                search(c)
                if folded {
                    Menu {
                        zoomButtons(c)
                        Divider()
                        pageTools(c)
                    } label: {
                        Label(.designMoreTools, systemImage: "ellipsis")
                    }
                    .help(Text(.designMoreTools))
                } else {
                    pageTools(c)
                }
            }
            if model.opensElsewhere { OpenElsewhereButton(url: model.url) }
        }
    }

    @ViewBuilder func zoomButtons(_ c: PDFController) -> some View {
        Button(.materialsViewerZoomOut, systemImage: "minus.magnifyingglass") { c.zoomOut() }.help(Text(.materialsViewerZoomOut))
        Button(.materialsViewerFit, systemImage: "arrow.up.left.and.arrow.down.right") { c.fit() }.help(Text(.materialsViewerFit))
        Button(.materialsViewerZoomIn, systemImage: "plus.magnifyingglass") { c.zoomIn() }.help(Text(.materialsViewerZoomIn))
    }

    @ViewBuilder func pageTools(_ c: PDFController) -> some View {
        if model.canSplit, model.splitting == nil {
            Button(.designPageRangeSplit, systemImage: "scissors") { Task { await model.startSplit(c) } }.help(Text(.designPageRangeSplitHelp))
        }
        if let link = model.pageLink(c.page) {
            Button(.fileViewCopyPageLink, systemImage: "link") { copyLink(link) }.help(Text(.fileViewCopyPageLink))
        }
        if let askClaude, model.material != nil {
            Button(.fileViewAskClaude, systemImage: "sparkle") {
                if let item = model.pageContext(c.page, in: c) { askClaude(item) }
            }
            .help(Text(.fileViewAskClaude))
        }
    }

    /// A see-through capsule like the window's search field. It measures its full width when the bar picks a row, and
    /// gives way down to `minWidth` only in the folded one.
    func search(_ c: PDFController) -> some View {
        HStack(spacing: Theme.Space.xs) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.Palette.textTertiary)
            TextField(String(localized: .materialsViewerSearch), text: $query).textFieldStyle(.plain)
                .frame(minWidth: 64, idealWidth: 160, maxWidth: 160)
                .onSubmit { c.find(query) }
            if !c.matches.isEmpty {
                Text("\(c.matchIndex + 1)/\(c.matches.count)").font(Theme.Typeface.caption).monospacedDigit().foregroundStyle(Theme.Palette.textTertiary)
                    .fixedSize()
                Button { c.step(-1) } label: { Image(systemName: "chevron.up") }.buttonStyle(.ghost)
                Button { c.step(1) } label: { Image(systemName: "chevron.down") }.buttonStyle(.ghost)
            }
        }
        .toolbarField()
    }

    func takeSplitAsk() {
        guard let ask = model.workspace.splitAsk, ask == model.material?.id, let c = pdf else { return }
        model.workspace.splitAsk = nil
        Task { await model.startSplit(c) }
    }

    func takeRequestedPage() -> Int? {
        defer { requestedPage = nil }
        return requestedPage
    }
}

/// A PDF, or the split screen over it while a split is edited (#321).
struct PDFContent: View {
    let model: FileViewModel
    let controller: PDFController
    var thumbnails = true

    var body: some View {
        if let shown = model.splitting, let course = model.course {
            // Closing leaves the screen's views drawn once more through this binding: they read the split as it was
            // shown, and a write after closing doesn't open it again. A stand-in split here had one zone, and a row
            // still holding the third ran off its end (#179).
            LectureSplitPane(controller: controller, split: Binding(get: { model.splitting ?? shown },
                                                                     set: { if model.splitting != nil { model.splitting = $0 } }),
                             units: course.file.units, note: model.splitNote, save: model.saveSplit, cancel: model.cancelSplit)
                .courseAccent(model.workspace.accent(course.id))
        } else if let course = model.course {
            PDFPane(controller: controller, thumbnails: thumbnails, workspace: model.workspace, course: course.id, material: model.material?.id)
                .courseAccent(model.workspace.accent(course.id))
        } else {
            PDFPane(controller: controller, thumbnails: thumbnails, workspace: model.workspace)
        }
    }
}

/// The way out to another app, for what Folio only shows: the file's default app on a Mac, the share sheet on iPad,
/// which has no default app to hand a file to.
struct OpenElsewhereButton: View {
    let url: URL
    var prominent = false

    var body: some View {
        #if os(macOS)
        if prominent {
            Button(.materialsOpenWithDefault) { NSWorkspace.shared.open(url) }.buttonStyle(.prominent)
        } else {
            Button(.materialsOpenWithDefault, systemImage: "arrow.up.forward.app") { NSWorkspace.shared.open(url) }
                .help(Text(.materialsOpenWithDefault))
        }
        #else
        if prominent {
            ShareLink(item: url) { Text(.fileViewShare) }.buttonStyle(.prominent)
        } else {
            ShareLink(item: url) { Label(String(localized: .fileViewShare), systemImage: "square.and.arrow.up") }
        }
        #endif
    }
}
