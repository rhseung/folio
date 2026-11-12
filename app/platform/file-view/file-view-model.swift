import FolioActions
import FolioAI
import FolioDomain
import FolioMarkdown
import FolioStorage
import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Observation
import PDFKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// One file in a pane, whatever opened it: a course's material, a note shown as a source in review, or a file outside
/// any course (a semester's `_Admin`). Picks the renderer from the file's format and loads what that renderer needs.
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
        /// Quick Look has no view of this format either.
        case unsupported
    }

    let workspace: Workspace
    private let initial: LoadedCourse?
    let subject: Subject
    private(set) var loaded: Loaded = .loading
    /// The page the PDF was opened at, so leaving it there isn't logged as a new view.
    private var openedAt = 0
    /// Off where a PDF is looked at for something else (a review's source): the materials tab resumes where the user
    /// last read, not where a review happened to open it.
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

    /// A tracked text file or a `.tex` note is edited in place (`TextFileView`); any other text is only shown.
    var editsInPlace: Bool {
        guard format.renderer == .source, course != nil else { return false }
        switch subject {
        case .material: return material != nil
        case .note: return true
        case .file: return false
        }
    }

    // MARK: Splitting a lecture (#321)

    /// The split being edited, while the split screen is up.
    var splitting: LectureSplit?
    private(set) var splitNote: String?
    /// The outline and titles being read as the screen opens: Claude waits until they are.
    private(set) var readingSplit = false
    private(set) var askingClaude = false
    /// Claude was asked and gave no split: the one time the screen offers Claude again. Otherwise the user adjusts what
    /// is there by hand (2026-11-12 사용자).
    private(set) var claudeFailed = false
    /// Tests give a stand-in.
    @ObservationIgnored lazy var lectureClaude: LectureClaude? = course.map { LectureClaude.of(workspace, course: $0) }
    /// The first reading of a file not split yet. Tests give a stand-in.
    @ObservationIgnored lazy var findSplit: @MainActor (URL, [FolioDomain.Unit]) async -> LectureFinding = { [workspace, course] url, units in
        let claude = course.flatMap { workspace.claudeReady ? workspace.claude(for: $0) : nil }
        return await LectureReader.find(url, units: units, claude: claude)
    }
    /// Bumped by each read and each ask, so an answer that comes after a newer one is dropped.
    @ObservationIgnored private var splitRead = 0

    /// A course's lecture PDF can be split into its units.
    var canSplit: Bool {
        guard let m = material, let course, format.renderer == .pdf else { return false }
        return course.file.lectureFiles.contains { $0.id == m.id }
    }

    /// The course's split when it has one; otherwise the same proposal the add sheet makes, read again, so a proposal
    /// put off there is never lost.
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
        let found = await findSplit(url, file.units)
        guard read == splitRead else { return }
        readingSplit = false
        askingClaude = false
        // Left alone while it was read: a cut made meanwhile is the user's and stays.
        guard let current = splitting, current.sections.count == 1, current.sections[0].unit == nil else { return }
        switch found {
        case .found(let split, _):
            // Found sections need no line saying so: each row's ✦ marks what was matched, and its tooltip says how.
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

    /// Claude's reading again, after it gave none. It is still only a proposal: nothing is written until "저장".
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

    private func closeSplit() {
        splitting = nil
        splitNote = nil
        splitRead += 1
        readingSplit = false
        askingClaude = false
        claudeFailed = false
    }

    /// A note is the app's own document: it has no other app to go to.
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

    /// Downloads an iCloud placeholder first: every renderer reads the file itself.
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

    /// Quick Look has no call that says whether it can show a file. A type no app on the device declares (`hwp`
    /// without Hancom) it can't; for the rest, a file it can show it can also draw small, so a thumbnail that fails
    /// (not the file's icon, which every file has) means its preview would be only that icon too. A thumbnail that
    /// takes long is left to the preview to settle, rather than keeping the pane on a spinner.
    nonisolated static func quickLookShows(_ url: URL) async -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension), !type.isDynamic else { return false }
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 64, height: 64), scale: 1, representationTypes: .thumbnail)
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

    /// A note's embeds come from its course; a markdown file elsewhere shows only the links.
    var embeds: NoteEmbedSource? {
        guard let course else { return nil }
        return NoteEmbedSource(workspace: workspace, course: course, own: url)
    }

    // MARK: PDF

    /// The page this file was last left at, on any device.
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

    /// `page` is 0-based; the link names it 1-based, as `#page=N` does everywhere.
    func pageLink(_ page: Int) -> AppLink? {
        material.map { AppLink(.material, $0.id, anchor: .page(page + 1)) }
    }

    /// The page's text and picture for the Claude panel. Nil off a course material: the panel belongs to a course.
    func pageContext(_ page: Int, in controller: PDFController) -> ContextItem? {
        guard let m = material, let pdfPage = controller.view.document?.page(at: page) else { return nil }
        let name = "\((m.path as NSString).lastPathComponent) p\(page + 1).jpg"
        return ContextBuilder.materialPage(id: m.id, path: m.path, page: page + 1, text: pdfPage.string ?? "",
                                           image: Self.jpeg(of: pdfPage).map { ContextItem.Image(name: name, data: $0) })
    }

    /// 1568px on the long edge, as the panel sends a note's pictures: Claude scales anything larger down to that.
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

    /// `page` is 0-based. While a class is recorded, the lecture pages it goes through are kept with the recording.
    func showing(_ page: Int) {
        guard let m = material, let course else { return }
        workspace.showing(page: page + 1, of: m, course: course.id)
    }
}
