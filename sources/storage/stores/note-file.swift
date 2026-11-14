import FolioDomain
import FolioMarkdown
import Foundation

public struct NoteFile: Equatable, Sendable {
    public var url: URL
    public var meta: NoteMeta
    public var title: String { url.deletingPathExtension().lastPathComponent }
    public var format: NoteFormat { NoteFormat(path: url.path) ?? .markdown }

    public init(url: URL, meta: NoteMeta) {
        self.url = url
        self.meta = meta
    }
}
