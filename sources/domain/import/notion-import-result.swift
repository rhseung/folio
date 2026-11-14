import Foundation

public struct NotionImportResult: Sendable, Equatable {
    public var transcript: Transcript
    public var catalog: Catalog
    public var courseFiles: [String: CourseFile]
    public var warnings: [String]

    public init(transcript: Transcript, catalog: Catalog, courseFiles: [String: CourseFile], warnings: [String]) {
        self.transcript = transcript
        self.catalog = catalog
        self.courseFiles = courseFiles
        self.warnings = warnings
    }
}
