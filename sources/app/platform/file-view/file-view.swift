import FolioDomain
import FolioStorage
import SwiftUI

struct FileView: View {
    @State private var model: FileViewModel
    @Binding private var requestedPage: Int?
    @Binding private var shownPage: Int?
    @State private var thumbnails = true
    @State private var query = ""
    @Environment(\.askClaude) private var askClaude

    init(
        workspace: Workspace, course: LoadedCourse, material: UUID, requestedPage: Binding<Int?> = .constant(nil),
        shownPage: Binding<Int?> = .constant(nil), remembersPage: Bool = true
    ) {
        _model = State(
            initialValue: FileViewModel(workspace: workspace, course: course, subject: .material(material), remembersPage: remembersPage))
        _requestedPage = requestedPage
        _shownPage = shownPage
    }

    init(workspace: Workspace, course: LoadedCourse, note: NoteFile) {
        _model = State(initialValue: FileViewModel(workspace: workspace, course: course, subject: .note(note)))
        _requestedPage = .constant(nil)
        _shownPage = .constant(nil)
    }

    init(workspace: Workspace, url: URL) {
        _model = State(initialValue: FileViewModel(workspace: workspace, course: nil, subject: .file(url)))
        _requestedPage = .constant(nil)
        _shownPage = .constant(nil)
    }

    var body: some View {
        if model.editsInPlace, let course = model.course {
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
            if model.opensElsewhere || isPDF || model.material != nil { bar }
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.card)
        .crumb(model.name, level: 2, symbol: model.symbol)
        .task(id: model.url) { await model.load(page: takeRequestedPage()) }
        .onChange(of: pdf?.page) { _, page in
            guard let page else { return }
            model.showing(page)
            shownPage = page
        }
        .onChange(of: model.recording) { _, recording in if recording != nil, let page = pdf?.page { model.showing(page) } }
        .onChange(of: requestedPage) { _, page in
            if page != nil, let pdf, let page = takeRequestedPage() { pdf.go(to: page) }
        }
        .onDisappear { model.closed(at: pdf?.page) }
        .onChange(of: pdf == nil, initial: true) { _, _ in model.takeSplitAsk(pdf) }
        .onChange(of: model.splitAsk) { _, _ in model.takeSplitAsk(pdf) }
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
            NotePreview(
                text: text, baseURL: model.url.deletingLastPathComponent(), math: model.math, embeds: model.embeds,
                revision: model.notesRevision)
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

    var bar: some View {
        ViewThatFits(in: .horizontal) {
            barRow(folded: false)
            barRow(folded: true)
        }
        // 보이는 줄과 상관없이 확대 키를 여기 둔다. 접힌 메뉴의 항목은 닫혀 있는 동안 키를 받지 않고, 두 줄에 두면 같은 키를 두 번 차지한다.
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
                    Button(.materialsViewerThumbnails, systemImage: "sidebar.squares.left") { thumbnails.toggle() }.help(
                        Text(.materialsViewerThumbnails))
                }
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
            if let m = model.material, let course = model.course {
                PageMenuButton(inBar: true) { MaterialMenu(courseId: course.id, materialId: m.id, host: .own) }
            }
        }
    }

    @ViewBuilder func zoomButtons(_ c: PDFController) -> some View {
        Button(.materialsViewerZoomOut, systemImage: "minus.magnifyingglass") { c.zoomOut() }.help(Text(.materialsViewerZoomOut))
        Button(.materialsViewerFit, systemImage: "arrow.up.left.and.arrow.down.right") { c.fit() }.help(Text(.materialsViewerFit))
        Button(.materialsViewerZoomIn, systemImage: "plus.magnifyingglass") { c.zoomIn() }.help(Text(.materialsViewerZoomIn))
    }

    @ViewBuilder func pageTools(_ c: PDFController) -> some View {
        if model.canSplit, model.splitting == nil {
            Button(.designPageRangeSplit, systemImage: "scissors") { Task { await model.startSplit(c) } }.help(
                Text(.designPageRangeSplitHelp))
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

    func search(_ c: PDFController) -> some View {
        HStack(spacing: Theme.Space.xs) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.Palette.textTertiary)
            TextField(String(localized: .materialsViewerSearch), text: $query).textFieldStyle(.plain)
                .frame(minWidth: 64, idealWidth: 160, maxWidth: 160)
                .onSubmit { c.find(query) }
            if !c.matches.isEmpty {
                Text("\(c.matchIndex + 1)/\(c.matches.count)").font(Theme.Typeface.caption).monospacedDigit().foregroundStyle(
                    Theme.Palette.textTertiary
                )
                .fixedSize()
                Button {
                    c.step(-1)
                } label: {
                    Image(systemName: "chevron.up")
                }.buttonStyle(.ghost)
                Button {
                    c.step(1)
                } label: {
                    Image(systemName: "chevron.down")
                }.buttonStyle(.ghost)
            }
        }
        .toolbarField()
    }

    func takeRequestedPage() -> Int? {
        defer { requestedPage = nil }
        return requestedPage
    }
}
