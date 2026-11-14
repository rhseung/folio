import Foundation

public struct NoteRetitle: Equatable, Sendable {
    public var note: UUID
    public var path: String
    public var title: String

    public init(note: UUID, path: String, title: String) {
        self.note = note
        self.path = path
        self.title = title
    }
}
