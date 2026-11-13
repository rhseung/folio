import FolioDomain
import FolioMarkdown
import Foundation

/// A note from before #206, whose frontmatter still holds Folio's properties.
public struct FrontmatterNote: Sendable, Equatable {
    public var url: URL
    public var meta: NoteMeta
    /// The file with Folio's keys taken out. Keys Folio never wrote stay, and the block goes only when nothing is left.
    public var text: String
}

extension CourseStore {
    /// Markdown notes still carrying Folio's frontmatter keys, read once by `note migrate` to move them to course.json.
    public func frontmatterNotes() throws -> [FrontmatterNote] {
        try noteURLs().filter { NoteFormat(path: $0.path) == .markdown }.compactMap { url in
            let (fm, body) = Frontmatter.split(String(decoding: try CoordinatedFile.read(url), as: UTF8.self))
            guard NoteMeta.frontmatterKeys.contains(where: { fm[$0] != nil }) else { return nil }
            var rest = fm
            for key in NoteMeta.frontmatterKeys { rest[key] = nil }
            return FrontmatterNote(url: url, meta: NoteMeta(frontmatter: fm), text: rest.render(body: body))
        }.sorted { $0.url.path < $1.url.path }
    }
}
