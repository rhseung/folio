import FolioDomain
import FolioMarkdown
import Foundation

public struct FrontmatterNote: Sendable, Equatable {
    public var url: URL
    public var meta: NoteMeta
    public var text: String
}

extension CourseStore {
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
