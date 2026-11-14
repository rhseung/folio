import FolioActions
import FolioDomain
import FolioStorage
import Foundation

struct CourseRef: Identifiable {
    var course: Course
    var store: CourseStore
    var file: CourseFile
    var code: String
    var color = ""

    var id: UUID { course.id }
    var tag: String { code.course(color) }
}
