import FolioDomain
import PDFKit
import SwiftUI

/// A PDF read inside the course: thumbnails, find, zoom, and the last page remembered across devices.
struct MaterialViewer: View {
    @Environment(Workspace.self) private var workspace
    let course: LoadedCourse
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
                ContentUnavailableView("PDF를 열 수 없습니다", systemImage: "doc.questionmark", description: Text(material.path))
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
            if let controller, controller.page != openedAt { workspace.recordPage(controller.page, of: material.id, course: course.id) }
        }
    }

    /// Page and zoom lead; search and opening elsewhere trail, as in Preview.
    func bar(_ c: PDFController) -> some View {
        PageBar {
            Button("페이지 미리보기", systemImage: "sidebar.left") { thumbnails.toggle() }.help("페이지 미리보기")
            Text("\(c.page + 1) / \(c.pageCount)").monospacedDigit().foregroundStyle(Theme.Palette.textSecondary).padding(.horizontal, Theme.Space.xs)
            Button("축소", systemImage: "minus.magnifyingglass") { c.zoomOut() }.keyboardShortcut("-")
            Button("화면에 맞추기", systemImage: "arrow.up.left.and.arrow.down.right") { c.fit() }.help("화면에 맞추기").keyboardShortcut("0")
            Button("확대", systemImage: "plus.magnifyingglass") { c.zoomIn() }.keyboardShortcut("=")
        } trailing: {
            // A see-through capsule like the window's search field.
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.Palette.textTertiary)
                TextField("본문 검색", text: $query).textFieldStyle(.plain).frame(width: 160).onSubmit { c.find(query) }
                if !c.matches.isEmpty {
                    Text("\(c.matchIndex + 1)/\(c.matches.count)").font(Theme.Typeface.caption).monospacedDigit().foregroundStyle(Theme.Palette.textTertiary)
                    Button { c.step(-1) } label: { Image(systemName: "chevron.up") }.buttonStyle(.ghost)
                    Button { c.step(1) } label: { Image(systemName: "chevron.down") }.buttonStyle(.ghost)
                }
            }
            .toolbarField()
            #if os(macOS)
            Button("기본 앱으로 열기", systemImage: "arrow.up.forward.app") { NSWorkspace.shared.open(course.store.fileURL(material.path)) }
                .help("기본 앱으로 열기")
            #endif
        }
    }

    func load() async {
        guard let url = try? await workspace.download(material, course: course.id), let document = PDFDocument(url: url) else {
            failed = true
            return
        }
        openedAt = workspace.lastPage(of: material.id, course: course.id) ?? 0
        controller = PDFController(document: document, page: openedAt)
    }
}
