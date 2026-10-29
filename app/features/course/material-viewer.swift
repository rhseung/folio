import FolioDomain
import PDFKit
import SwiftUI

struct MaterialViewer: View {
    let model: MaterialsModel
    let material: FolioDomain.Material
    @State private var controller: PDFController?
    @State private var failed = false
    @State private var openedAt = 0
    @State private var thumbnails = true
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            if let controller {
                bar(controller)
                HStack(spacing: 0) {
                    if thumbnails {
                        PDFThumbnails(controller: controller).frame(width: 128)
                        Theme.Palette.lineSoft.frame(width: 1)
                    }
                    PDFKitView(controller: controller)
                }
            } else if failed {
                // Fills the rest so the bar stays on top; unsized, the VStack centers bar and message together.
                ContentUnavailableView(String(localized: .materialsViewerCannotOpen), systemImage: "doc.questionmark", description: Text(material.path))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.card)
        .crumb((material.path as NSString).lastPathComponent, level: 2, symbol: "doc")
        .task(id: material.id) { await load() }
        .onDisappear {
            if let controller, controller.page != openedAt { model.recordPage(controller.page, of: material) }
        }
    }

    /// Page and zoom lead; search and opening elsewhere trail, as in Preview.
    func bar(_ c: PDFController) -> some View {
        PageBar {
            Button(.materialsViewerThumbnails, systemImage: "sidebar.left") { thumbnails.toggle() }.help(Text(.materialsViewerThumbnails))
            Text("\(c.page + 1) / \(c.pageCount)").monospacedDigit().foregroundStyle(Theme.Palette.textSecondary).padding(.horizontal, Theme.Space.xs)
            Button(.materialsViewerZoomOut, systemImage: "minus.magnifyingglass") { c.zoomOut() }.keyboardShortcut("-")
            Button(.materialsViewerFit, systemImage: "arrow.up.left.and.arrow.down.right") { c.fit() }.help(Text(.materialsViewerFit)).keyboardShortcut("0")
            Button(.materialsViewerZoomIn, systemImage: "plus.magnifyingglass") { c.zoomIn() }.keyboardShortcut("=")
        } trailing: {
            // A see-through capsule like the window's search field.
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.Palette.textTertiary)
                TextField(String(localized: .materialsViewerSearch), text: $query).textFieldStyle(.plain).frame(width: 160).onSubmit { c.find(query) }
                if !c.matches.isEmpty {
                    Text("\(c.matchIndex + 1)/\(c.matches.count)").font(Theme.Typeface.caption).monospacedDigit().foregroundStyle(Theme.Palette.textTertiary)
                    Button { c.step(-1) } label: { Image(systemName: "chevron.up") }.buttonStyle(.ghost)
                    Button { c.step(1) } label: { Image(systemName: "chevron.down") }.buttonStyle(.ghost)
                }
            }
            .toolbarField()
            #if os(macOS)
            Button(.materialsOpenWithDefault, systemImage: "arrow.up.forward.app") { NSWorkspace.shared.open(model.fileURL(material.path)) }
                .help(Text(.materialsOpenWithDefault))
            #endif
        }
    }

    func load() async {
        guard let pdf = await model.pdf(material), let document = PDFDocument(url: pdf.url) else {
            failed = true
            return
        }
        openedAt = pdf.page
        controller = PDFController(document: document, page: openedAt)
    }
}
