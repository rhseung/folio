import Foundation

public struct World: Sendable {
    public var catalog: Catalog?
    public var transcript: Transcript?
    public var courseFiles: [CourseFile]?

    public init(catalog: Catalog? = nil, transcript: Transcript? = nil, courseFiles: [CourseFile]? = nil) {
        (self.catalog, self.transcript, self.courseFiles) = (catalog, transcript, courseFiles)
    }
}
