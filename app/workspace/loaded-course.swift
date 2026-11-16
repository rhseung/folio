import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Observation

struct LoadedCourse: Identifiable {
    var store: CourseStore
    var document: StoredDocument<CourseFile>
    var id: UUID { document.model.course.id }
    var file: CourseFile { document.model }
    var title: String { file.course.title }
}
