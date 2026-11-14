import FolioDomain
import FolioMarkdown
import Foundation

public struct FrontmatterNote: Sendable, Equatable {
    public var url: URL
    public var meta: NoteMeta
    public var text: String
}
