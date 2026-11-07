import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Observation

/// One text file of a course open for editing, and for a `.tex` its PDF: beside a material, where `note build` puts a
/// note's.
@MainActor @Observable
final class TextFileModel {
    enum Source {
        case material(UUID)
        case note(NoteFile)
    }

    let workspace: Workspace
    private let initial: LoadedCourse
    let source: Source
    var text = ""
    /// The file as last read or written here. A save finding something else on disk was changed elsewhere (another
    /// device, the CLI) and asks before overwriting it.
    private var onDisk = ""
    private(set) var loaded = false
    private(set) var unreadable = false
    var conflict = false
    var reveal: Int?
    private(set) var building = false
    private(set) var issues: [TexIssue] = []
    /// Bumped after a build so the preview reopens the PDF, which keeps its name.
    private(set) var pdfRevision = 0
    /// A build that would replace a PDF Folio didn't make, held until the user says to.
    private var held: URL?
    var asksToReplace = false
    let engineMissing: Bool

    convenience init(workspace: Workspace, course: LoadedCourse, material: UUID) {
        self.init(workspace: workspace, course: course, source: .material(material))
    }

    init(workspace: Workspace, course: LoadedCourse, source: Source) {
        self.workspace = workspace
        initial = course
        self.source = source
        #if os(macOS)
        engineMissing = TexEngine.locate() == nil
        #else
        engineMissing = true
        #endif
    }

    var course: LoadedCourse { workspace.course(initial.id) ?? initial }
    var path: String {
        switch source {
        case let .material(id): course.file.materials.first { $0.id == id }?.path ?? ""
        case let .note(note): course.store.notePath(of: note.url)
        }
    }

    /// What `PaneMemory` keeps this file's view under: a `.tex` opens the way it was left, as a markdown note does.
    var paneId: UUID? {
        switch source {
        case let .material(id): id
        case let .note(note): note.meta.id
        }
    }

    var name: String { (path as NSString).lastPathComponent }
    var format: MaterialFormat { MaterialFormat(path: path) }
    var isTex: Bool { format == .tex }
    var dirty: Bool { loaded && text != onDisk }

    /// The tracked PDF beside this source, or where a first build will put it. A note's goes where `note build` puts
    /// it, which depends on its kind; the link menu on this screen can change that after the note was opened, so the
    /// entry is read again rather than taken from `source`.
    var pdfPath: String {
        switch source {
        case let .material(id):
            let source = course.file.materials.first { $0.id == id }
            return source.flatMap { course.file.materials.builtPDF(of: $0) }?.path ?? MaterialFormat.builtPDF(of: path) ?? path
        case let .note(note):
            return course.store.exportPath(of: course.store.note(at: path, in: course.file) ?? note)
        }
    }
    var pdfName: String { (pdfPath as NSString).lastPathComponent }
    var pdfURL: URL? {
        let url = course.store.fileURL(pdfPath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    #if os(macOS)
    var canBuild: Bool { isTex && !engineMissing && !building }
    #else
    // Tectonic runs as a separate program, which iPadOS doesn't allow.
    var canBuild: Bool { false }
    #endif

    var fileURL: URL { course.store.fileURL(path) }
    var errors: [TexIssue] { issues.filter { $0.severity == .error } }
    var shownIssues: [TexIssue] { errors + issues.filter { $0.severity == .warning } }

    /// A file that can't be read (not downloaded yet, gone, not UTF-8) leaves the editor closed: an empty editor would
    /// look like an empty file, and saving it would replace the real one.
    func load() {
        do {
            onDisk = try course.store.readText(path)
            text = onDisk
            loaded = true
            unreadable = false
        } catch {
            loaded = false
            unreadable = true
        }
    }

    /// A material written elsewhere in the app moves only its hash in course.json; a note, or anything written outside
    /// the app (another device, the CLI), moves `notesRevision`.
    var outsideRevision: String {
        let hash = if case let .material(id) = source { course.file.materials.first { $0.id == id }?.hash } else { String?.none }
        return "\(workspace.notesRevision) \(hash ?? "")"
    }

    /// As the note editor does: this screen's own save left `onDisk` as the file is, and unsaved edits ask instead.
    func refresh() {
        guard loaded, let disk = try? course.store.readText(path), disk != onDisk else { return }
        if dirty {
            conflict = true
        } else {
            onDisk = disk
            text = disk
        }
    }

    func saveNow(force: Bool) {
        guard loaded, !conflict || force else { return }
        let writing = text
        do {
            let expected = force ? nil : onDisk
            switch source {
            case let .material(id): _ = try workspace.runThrowing(MaterialWrite(course: course.id, material: id, text: writing, expected: expected))
            case .note: _ = try workspace.runThrowing(NoteWrite(course: course.id, note: path, text: writing, expected: expected))
            }
            onDisk = writing
            conflict = false
        } catch ActionError.conflict {
            conflict = true
        } catch {
            workspace.error = "\(error)"
        }
    }

    func saveIfDirty() { if dirty { saveNow(force: false) } }

    /// Saves first, so the PDF shows what's on screen. Tectonic runs off the main thread; the action then only places
    /// the PDF it made.
    func build() async {
        #if os(macOS)
        guard canBuild, let engine = TexEngine.locate() else { return }
        saveIfDirty()
        guard !dirty else { return }
        building = true
        defer { building = false }
        let file = course.store.fileURL(path)
        let (now, calendar) = (workspace.now, workspace.calendar)
        let result: TexEngine.Build
        do {
            result = try await Task.detached { try engine.compile(file, into: TexEngine.outputFolder(for: file), at: now, calendar: calendar) }.value
        } catch {
            issues = [TexIssue(.error, message: error.localizedDescription)]
            return
        }
        issues = result.issues
        guard let pdf = result.pdf else { return }
        place(pdf, overwrite: false)
        #endif
    }

    #if os(macOS)
    /// A ⌘-click on the PDF (page 0-based, point from the page's top-left corner) puts the caret on the line that wrote
    /// there. Only this file's lines: an `\input` file is not open here.
    func showSource(page: Int, at point: CGPoint) {
        guard isTex, let shown = pdfURL, let sync = TexEngine.syncTeX(for: fileURL, showing: shown),
              let place = sync.place(page: page + 1, x: point.x, y: point.y),
              URL(filePath: place.file).resolvingSymlinksInPath() == fileURL.resolvingSymlinksInPath() else { return }
        reveal = place.line
    }
    #endif

    func replace() {
        guard let held else { return }
        place(held, overwrite: true)
    }

    private func place(_ pdf: URL, overwrite: Bool) {
        held = nil
        do {
            switch source {
            case let .material(id): _ = try workspace.runThrowing(MaterialBuild(course: course.id, material: id, pdf: pdf.path, overwrite: overwrite))
            case .note: _ = try workspace.runThrowing(NoteBuild(course: course.id, note: path, pdf: pdf.path, overwrite: overwrite))
            }
            pdfRevision += 1
        } catch ActionError.conflict {
            held = pdf
            asksToReplace = true
        } catch {
            workspace.error = "\(error)"
        }
    }

    /// Only problems in this file can be shown; an `\input` file's line means nothing here. Tectonic runs in the
    /// document's folder and names files from there, so `sections/Problems.tex` is another file with the same name.
    func isHere(_ issue: TexIssue) -> Bool {
        guard let file = issue.file, issue.line != nil else { return false }
        let relative = file.hasPrefix("./") ? String(file.dropFirst(2)) : file
        return relative == name || URL(filePath: file).standardizedFileURL == fileURL.standardizedFileURL
    }

    func jump(to issue: TexIssue) {
        guard isHere(issue), let line = issue.line else { return }
        reveal = line
    }

    func label(_ issue: TexIssue) -> String {
        guard let line = issue.line else { return issue.message }
        let place = isHere(issue) ? String(localized: .textFileLine(line)) : "\(issue.file ?? ""):\(line)"
        return "\(place) · \(issue.message)"
    }
}
