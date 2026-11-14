import Foundation

public struct NotionNotePlan: Sendable, Equatable {
    public var id: UUID
    public var title: String
    public var meta: NoteMeta
    public var sourceFile: String

    public init(id: UUID, title: String, meta: NoteMeta, sourceFile: String) {
        self.id = id
        self.title = title
        self.meta = meta
        self.sourceFile = sourceFile
    }
}
