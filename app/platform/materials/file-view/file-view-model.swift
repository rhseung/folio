import FolioAI
import FolioActions
import FolioDomain
import FolioMarkdown
import FolioStorage
import Foundation
import Observation
import PDFKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor @Observable
final class FileViewModel {
    enum Subject {
        case material(UUID)
        case note(NoteFile)
        case file(URL)
    }

    enum Loaded {
        case loading
        case failed
        case pdf(PDFController)
        case markdown(String)
        case source(String)
        case image(URL)
        case audio(URL)
        case quickLook(URL)
        case unsupported
    }

    let workspace: Workspace
    private let initial: LoadedCourse?
    let subject: Subject
    private(set) var loaded: Loaded = .loading
    private var openedAt = 0
    let remembersPage: Bool

    init(workspace: Workspace, course: LoadedCourse?, subject: Subject, remembersPage: Bool = true) {
        self.workspace = workspace
        initial = course
        self.subject = subject
        self.remembersPage = remembersPage
    }

    var course: LoadedCourse? { initial.map { workspace.course($0.id) ?? $0 } }

    var material: FolioDomain.Material? {
        guard case .material(let id) = subject else { return nil }
        return course?.file.materials.first { $0.id == id }
    }

    var url: URL {
        switch subject {
        case .material: material.flatMap { m in course.map { $0.store.fileURL(m.path) } } ?? URL(filePath: "/")
        case .note(let note): note.url
        case .file(let url): url
        }
    }

    var name: String { url.lastPathComponent }
    var format: MaterialFormat { MaterialFormat(path: url.path) }

    var editsInPlace: Bool {
        guard format.renderer == .source, course != nil else { return false }
        switch subject {
        case .material: return material != nil
        case .note: return true
        case .file: return false
        }
    }

    // MARK: Splitting a lecture (#321)

    var splitting: LectureSplit?
    private(set) var splitNote: String?
    private(set) var readingSplit = false
    private(set) var askingClaude = false
    private(set) var claudeFailed = false
    @ObservationIgnored lazy var lectureClaude: LectureClaude? = course.map { LectureClaude.of(workspace, course: $0) }
    @ObservationIgnored var findSplit: (@MainActor (URL, [FolioDomain.Unit]) async -> LectureFinding)?
    @ObservationIgnored private var splitRead = 0

    var canSplit: Bool {
        guard let m = material, let course, format.renderer == .pdf else { return false }
        return course.file.lectureFiles.contains { $0.id == m.id }
    }

    func startSplit(_ controller: PDFController) async {
        guard let m = material, let course, canSplit else { return }
        let file = course.file
        splitRead += 1
        askingClaude = false
        claudeFailed = false
        if file.isSplit(m.id) {
            splitting = LectureSplit(file: file, material: m.id, pageCount: controller.pageCount)
            splitNote = nil
            return
        }

        splitting = LectureSplit(pageCount: controller.pageCount)
        let claude = lectureClaude.map { $0.off() == nil } ?? false
        splitNote = String(localized: claude ? .lectureClaudeReading : .fileViewSplitReading)
        readingSplit = true
        askingClaude = claude
        let read = splitRead

        let found: LectureFinding
        if let findSplit {
            found = await findSplit(url, file.units)
        } else {
            found = await LectureReader.find(url, units: file.units, claude: workspace.claudeReady ? workspace.claude(for: course) : nil)
        }
        guard read == splitRead else { return }
        readingSplit = false
        askingClaude = false

        guard let current = splitting, current.sections.count == 1, current.sections[0].unit == nil else { return }
        switch found {
        case .found(let split, _):
            splitting = split
            splitNote = nil
        case .nothing, .unreadable:
            splitNote = String(localized: .fileViewSplitNothing)
        case .failed(let why, _):
            splitNote = why
            claudeFailed = true
        }
    }

    var canRetryClaude: Bool { claudeFailed && splitting != nil && !readingSplit && !askingClaude }

    func retryClaude() async {
        guard canRetryClaude, let claude = lectureClaude else { return }
        splitRead += 1
        let read = splitRead
        askingClaude = true
        splitNote = String(localized: .lectureClaudeReading)
        let found = await claude.ask(url, course?.file.units ?? [])
        guard read == splitRead, splitting != nil else { return }
        askingClaude = false
        if case .found(let split) = found {
            splitting = split
            claudeFailed = false
        }
        splitNote = found.message
    }

    func saveSplit() {
        guard let m = material, let course, let split = splitting else { return }
        if workspace.run(MaterialSplit(course: course.id, material: m.id, sections: split.cuts)) != nil { closeSplit() }
    }

    func cancelSplit() { closeSplit() }

    var splitAsk: UUID? { workspace.splitAsk }

    func takeSplitAsk(_ controller: PDFController?) {
        guard let ask = workspace.splitAsk, ask == material?.id, let controller else { return }
        workspace.splitAsk = nil
        Task { await startSplit(controller) }
    }

    private func closeSplit() {
        splitting = nil
        splitNote = nil
        splitRead += 1
        readingSplit = false
        askingClaude = false
        claudeFailed = false
    }

    var opensElsewhere: Bool {
        if case .note = subject { return false }
        return true
    }

    var symbol: String {
        switch format.renderer {
        case .pdf: "doc.richtext"
        case .markdown, .source: "doc.text"
        case .image: "photo"
        case .audio: "waveform"
        case .quickLook: "doc"
        }
    }

    // MARK: Loading

    // 모든 렌더러가 파일을 직접 읽으므로 iCloud 자리표시자를 먼저 내려받는다.
    func load(page requested: Int?) async {
        guard let file = await download() else {
            loaded = .failed
            return
        }
        switch format.renderer {
        case .pdf:
            guard let document = PDFDocument(url: file) else {
                loaded = .failed
                return
            }
            openedAt = lastPage() ?? 0
            loaded = .pdf(PDFController(document: document, page: requested.map { min($0, document.pageCount - 1) } ?? openedAt))
        case .markdown:
            guard let text = readText(file) else {
                loaded = .failed
                return
            }
            loaded = .markdown(Frontmatter.split(text).body)
        case .source:
            guard let text = readText(file) else {
                loaded = .failed
                return
            }
            loaded = .source(text)
        case .image: loaded = .image(file)
        case .audio: loaded = .audio(file)
        case .quickLook: loaded = await Self.quickLookShows(file) ? .quickLook(file) : .unsupported
        }
    }

    private func download() async -> URL? {
        switch subject {
        case .material:
            guard let m = material, let course else { return nil }
            return try? await workspace.download(m, course: course.id)
        case .note(let note):
            return note.url
        case .file(let url):
            return await Task.detached { LocalFile.download(url) }.value
        }
    }

    private func readText(_ file: URL) -> String? {
        if case .note(let note) = subject { return try? course?.store.read(note) }
        return LocalFile.read(file).flatMap { String(data: $0, encoding: .utf8) }
    }

    // Quick Look에는 파일을 보일 수 있는지 알려 주는 호출이 없다. 기기의 어느 앱도 선언하지 않은 형식(한컴 오피스가 없을 때의 `hwp`)은 보이지 못한다. 그 밖의 형식은 보일 수 있으면 작게도
    // 그릴 수 있으므로, 썸네일이 실패하면(모든 파일에 있는 파일 아이콘은 제외) 미리보기도 아이콘뿐이다. 썸네일이 오래 걸리면 칸을 로딩 표시로 붙잡아 두지 않고 미리보기에 판단을 맡긴다.
    nonisolated static func quickLookShows(_ url: URL) async -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension), !type.isDynamic else { return false }
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                let request = QLThumbnailGenerator.Request(
                    fileAt: url, size: CGSize(width: 64, height: 64), scale: 1, representationTypes: .thumbnail)
                return (try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)) != nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(3))
                return true
            }
            let first = await group.next() ?? true
            group.cancelAll()
            return first
        }
    }

    // MARK: Markdown

    var math: MathSyntax {
        if case .note(let note) = subject { return note.meta.math }
        return .latex
    }

    // 읽을 때마다 만들지 않고 남겨 둔다. 이 소스는 노트 리비전이 바뀔 때까지 읽은 노트를 가지고 있으므로, 본문마다 새로 만들면 연결된 노트를 모두 다시 읽는다.
    @ObservationIgnored private var embedSource: (url: URL, source: NoteEmbedSource)?

    var embeds: NoteEmbedSource? {
        guard let course else { return nil }
        let url = url
        if let kept = embedSource, kept.url == url { return kept.source }
        let source = NoteEmbedSource(workspace: workspace, course: course, own: url)
        embedSource = (url, source)
        return source
    }

    var notesRevision: Int { workspace.notesRevision }

    func accent(_ course: LoadedCourse) -> CourseAccent { workspace.accent(course.id) }

    // MARK: PDF

    func pageStrip(pageCount: Int) -> PageStripModel {
        PageStripModel(workspace: workspace, course: course?.id, material: material?.id, pageCount: pageCount)
    }

    private func lastPage() -> Int? {
        guard let m = material, let course else { return nil }
        return ((try? course.store.log.readAll()) ?? []).events(MaterialViewEvent.self).last { $0.event.materialId == m.id }?.event.page
    }

    func closed(at page: Int?) {
        guard let m = material, let course else { return }
        if remembersPage, let page, page != openedAt {
            let store = course.store
            // folio:not-an-action page views are activity logs, not data changes
            workspace.perform { try store.log.append(MaterialViewEvent(materialId: m.id, page: page), device: workspace.device, at: .now) }
        }
        workspace.showing(page: nil, of: m, course: course.id)
    }

    func pageLink(_ page: Int) -> AppLink? {
        material.map { AppLink(.material, $0.id, anchor: .page(page + 1)) }
    }

    func pageContext(_ page: Int, in controller: PDFController) -> ContextItem? {
        guard let m = material, let pdfPage = controller.view.document?.page(at: page) else { return nil }
        let name = "\((m.path as NSString).lastPathComponent) p\(page + 1).jpg"
        return ContextBuilder.materialPage(
            id: m.id, path: m.path, page: page + 1, text: pdfPage.string ?? "",
            image: Self.jpeg(of: pdfPage).map { ContextItem.Image(name: name, data: $0) })
    }

    private static func jpeg(of page: PDFPage) -> Data? {
        let bounds = page.bounds(for: .mediaBox)
        let scale = 1568 / max(bounds.width, bounds.height, 1)
        let image = page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
        #if os(macOS)
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
        #else
        return image.jpegData(compressionQuality: 0.8)
        #endif
    }

    var recording: UUID? { workspace.recorder.capturing }

    func showing(_ page: Int) {
        guard let m = material, let course else { return }
        workspace.showing(page: page + 1, of: m, course: course.id)
    }
}
