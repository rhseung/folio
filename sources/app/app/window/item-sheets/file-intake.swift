import FolioDomain
import FolioStorage
import SwiftUI

struct FileIntake: Identifiable, Equatable {
    let id = UUID()
    let course: UUID
    let folder: String
}
