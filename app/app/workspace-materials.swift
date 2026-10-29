import FolioActions
import FolioDomain
import FolioMarkdown
import FolioStorage
import Foundation

extension Workspace {
    /// Off the main actor: an iCloud placeholder downloads before this returns.
    func download(_ material: FolioDomain.Material, course id: UUID) async throws -> URL {
        guard let store = course(id)?.store else { throw CocoaError(.fileNoSuchFile) }
        return try await Task.detached { try store.download(material) }.value
    }

    /// Copies files in from outside into `folder` (docs/SPEC.md "구조 유지"), registers them, and links them to `session`.
    /// `week` puts the week in front of the name, as `Lectures` asks. A file already in this course is linked where it is.
    func importFiles(_ urls: [URL], into folder: String, week: Int? = nil, session: UUID? = nil, course id: UUID) {
        let files = urls.filter(\.isFileURL)
        // Files handed over from outside the sandbox stay readable only inside this scope.
        let scoped = files.filter { $0.startAccessingSecurityScopedResource() }
        defer { for url in scoped { url.stopAccessingSecurityScopedResource() } }
        run(MaterialImport(course: id, files: files.map { $0.path(percentEncoded: false) }, folder: folder, week: week, session: session))
    }
}
