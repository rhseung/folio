import Foundation

public struct NotionCourseDump: Codable, Sendable {
    public struct NoteRow: Codable, Sendable {
        public var id: UUID
        public var title: String
        public var kind: String?
        public var date: String?
        public var file: String?
    }

    public struct ScoreRow: Codable, Sendable {
        public var id: UUID
        public var name: String
        public var weight: Double?
        public var score: Double?
        public var max: Double?
        public var parentId: UUID?
    }

    public struct ImageRow: Codable, Sendable {
        public var source: String
        public var file: String?

        public init(source: String, file: String?) {
            self.source = source
            self.file = file
        }
    }

    public var coursePageId: UUID
    public var title: String
    public var notes: [NoteRow]
    public var scores: [ScoreRow]
    public var images: [ImageRow]

    public init(coursePageId: UUID, title: String, notes: [NoteRow], scores: [ScoreRow], images: [ImageRow]) {
        self.coursePageId = coursePageId
        self.title = title
        self.notes = notes
        self.scores = scores
        self.images = images
    }
}
