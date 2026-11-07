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

    /// Copies files in from outside, each into its folder, registers them, and links each to its session. A lecture
    /// takes its session's week in front of its name, and the sections approved in the add sheet (#321). A file already
    /// in this course is linked where it is.
    func importFiles(_ files: [(url: URL, folder: String, session: UUID?, sections: [LectureCut]?)], course id: UUID) {
        let files = files.filter(\.url.isFileURL)
        // Files handed over from outside the sandbox stay readable only inside this scope.
        let scoped = files.map(\.url).filter { $0.startAccessingSecurityScopedResource() }
        defer { for url in scoped { url.stopAccessingSecurityScopedResource() } }
        run(MaterialImport(course: id, items: files.map { ImportItem(file: $0.url.path(percentEncoded: false), folder: $0.folder, session: $0.session, sections: $0.sections) }))
    }

    func importFiles(_ urls: [URL], into folder: String, session: UUID? = nil, course id: UUID) {
        importFiles(urls.map { ($0, folder, session, nil) }, course: id)
    }
}
