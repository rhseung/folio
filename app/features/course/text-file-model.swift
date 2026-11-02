import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Observation

/// One text file of a course open for editing, and for a `.tex` its PDF beside it.
@MainActor @Observable
final class TextFileModel {
    let workspace: Workspace
    private let initial: LoadedCourse
    let materialId: UUID
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

    init(workspace: Workspace, course: LoadedCourse, material: UUID) {
        self.workspace = workspace
        initial = course
        materialId = material
        #if os(macOS)
        engineMissing = TexEngine.locate() == nil
        #else
        engineMissing = true
        #endif
    }

    var course: LoadedCourse { workspace.course(initial.id) ?? initial }
    var material: FolioDomain.Material? { course.file.materials.first { $0.id == materialId } }
    var path: String { material?.path ?? "" }
    var name: String { (path as NSString).lastPathComponent }
    var format: MaterialFormat { MaterialFormat(path: path) }
    var isTex: Bool { format == .tex }
    var dirty: Bool { loaded && text != onDisk }

    /// The PDF tracking linked to this source, or where a first build will put it.
    var pdfPath: String {
        course.file.materials.first { $0.id == material?.sourceOf }?.path ?? MaterialFormat.builtPDF(of: path) ?? path
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

    func saveNow(force: Bool) {
        guard loaded, !conflict || force else { return }
        let writing = text
        do {
            _ = try workspace.runThrowing(MaterialWrite(course: course.id, material: materialId, text: writing, expected: force ? nil : onDisk))
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
        let source = course.store.fileURL(path)
        let result: TexEngine.Build
        do {
            result = try await Task.detached { try engine.compile(source, into: TexEngine.outputFolder(for: source)) }.value
        } catch {
            issues = [TexIssue(.error, message: error.localizedDescription)]
            return
        }
        issues = result.issues
        guard let pdf = result.pdf else { return }
        place(pdf, overwrite: false)
        #endif
    }

    func replace() {
        guard let held else { return }
        place(held, overwrite: true)
    }

    private func place(_ pdf: URL, overwrite: Bool) {
        held = nil
        do {
            _ = try workspace.runThrowing(MaterialBuild(course: course.id, material: materialId, pdf: pdf.path, overwrite: overwrite))
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
