import FolioActions
import FolioDomain
import FolioMarkdown
import FolioStorage
import Foundation

extension Workspace {
    // iCloud 자리표시 파일은 반환하기 전에 내려받으므로 main actor 밖에서 실행한다.
    func download(_ material: FolioDomain.Material, course id: UUID) async throws -> URL {
        guard let store = course(id)?.store else { throw CocoaError(.fileNoSuchFile) }
        return try await Task.detached { try store.download(material) }.value
    }

    func importFiles(_ files: [(url: URL, folder: String, session: UUID?, sections: [LectureCut]?)], course id: UUID) {
        let files = files.filter(\.url.isFileURL)
        // sandbox 밖에서 넘겨받은 파일은 이 scope 안에서만 읽을 수 있다.
        let scoped = files.map(\.url).filter { $0.startAccessingSecurityScopedResource() }
        defer { for url in scoped { url.stopAccessingSecurityScopedResource() } }
        run(
            MaterialImport(
                course: id,
                items: files.map {
                    ImportItem(file: $0.url.path(percentEncoded: false), folder: $0.folder, session: $0.session, sections: $0.sections)
                }))
    }

    func importFiles(_ urls: [URL], into folder: String, session: UUID? = nil, course id: UUID) {
        importFiles(urls.map { ($0, folder, session, nil) }, course: id)
    }
}
