import FolioDomain
import FolioMarkdown
import Foundation

extension CourseStore {
    /// Notes whose ID already exists and existing assets are left alone.
    public func writeNotionNotes(_ plans: [NotionNotePlan], dump: NotionCourseDump, folder: URL, links: [String: String]) throws {
        guard !plans.isEmpty else { return }
        var images: [String: String] = [:]
        for image in dump.images {
            guard let file = image.file else { continue }
            let source = folder.appending(path: file)
            if FileManager.default.fileExists(atPath: source.path) { images[image.source] = try addNoteAsset(source) }
        }
        let existing = Set(try notes().compactMap(\.meta.id))
        for plan in plans where !existing.contains(plan.id) {
            let raw = String(decoding: try Data(contentsOf: folder.appending(path: plan.sourceFile)), as: UTF8.self)
            let body = "# \(plan.title)\n\n" + NotionMarkdown.convert(raw, links: links, images: images) + "\n"
            _ = try createNote(title: plan.title, meta: plan.meta, body: body)
        }
    }

    public func assignmentFolders() throws -> [String] {
        let url = url.appending(path: CourseFolder.assignments.rawValue)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try FolderTree(contentsOf: url, depth: 1).children.filter { !$0.isFile }.map(\.name)
    }
}
