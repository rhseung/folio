import FolioDomain
import FolioStorage
import Foundation

struct CourseChatFile {
    var course: UUID
    var doc: StoredDocument<Chat>
}
