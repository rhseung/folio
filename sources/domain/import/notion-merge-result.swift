import Foundation

public struct NotionMergeResult: Sendable {
    public var file: CourseFile
    public var notes: [NotionNotePlan]
    public var sessionsAdded: Int
    public var componentsAdded: Int
    public var scoresAdded: Int
    public var warnings: [String]
}
