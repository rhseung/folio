import FolioDomain
import FolioStorage
import Foundation

public struct ReadCourse {
    public let file: CourseFile
    public let store: CourseStore
    public let code: String

    public var id: UUID { file.course.id }
}
