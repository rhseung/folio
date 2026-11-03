import FolioDomain
import FolioMarkdown
import Foundation

extension CourseStore {
    /// Writes each plan that has a place in `urls`; existing assets are left alone. The caller picks the places, so a
    /// dry run reports the same paths, and adds the entries to course.json.
    public func writeNotionNotes(_ plans: [NotionNotePlan], dump: NotionCourseDump, folder: URL, links: [String: String], at urls: [UUID: URL]) throws {
        guard plans.contains(where: { urls[$0.id] != nil }) else { return }
        var images: [String: String] = [:]
        for image in dump.images {
            guard let file = image.file else { continue }
            let source = folder.appending(path: file)
            if FileManager.default.fileExists(atPath: source.path) { images[image.source] = try addNoteAsset(source) }
        }
        for plan in plans {
            guard let url = urls[plan.id] else { continue }
            let raw = String(decoding: try Data(contentsOf: folder.appending(path: plan.sourceFile)), as: UTF8.self)
            let body = "# \(plan.title)\n\n" + NotionMarkdown.convert(raw, links: links, images: images) + "\n"
            try createNote(at: url, text: body)
        }
    }

    public func assignmentFolders() throws -> [String] {
        let url = url.appending(path: CourseFolder.assignments.rawValue)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try FolderTree(contentsOf: url, depth: 1).children.filter { !$0.isFile }.map(\.name)
    }
}
