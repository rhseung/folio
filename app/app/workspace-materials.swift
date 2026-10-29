import FolioActions
import FolioDomain
import FolioMarkdown
import FolioStorage
import Foundation

extension Workspace {
    /// The page this PDF was last left at on any device.
    func lastPage(of material: UUID, course id: UUID) -> Int? {
        guard let course = course(id) else { return nil }
        return ((try? course.store.log.readAll()) ?? [])
            .events(MaterialViewEvent.self)
            .last { $0.event.materialId == material }?.event.page
    }

    func recordPage(_ page: Int, of material: UUID, course id: UUID) {
        guard let course = course(id) else { return }
        // folio:not-an-action page views are activity logs, not data changes (docs/SPEC.md "액션")
        perform { try course.store.log.append(MaterialViewEvent(materialId: material, page: page), device: device, at: .now) }
    }

    /// Off the main actor: an iCloud placeholder downloads before this returns.
    func download(_ material: FolioDomain.Material, course id: UUID) async throws -> URL {
        guard let store = course(id)?.store else { throw CocoaError(.fileNoSuchFile) }
        return try await Task.detached { try store.download(material) }.value
    }

    func relink(_ material: UUID, to file: URL, course id: UUID) {
        // Files picked on iPadOS are security-scoped; reading the hash needs access.
        let scoped = file.startAccessingSecurityScopedResource()
        defer { if scoped { file.stopAccessingSecurityScopedResource() } }
        run(MaterialRelink(course: id, material: material, file: file.path(percentEncoded: false)))
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
