import FolioDomain
import FolioStorage
import SwiftUI

struct MaterialSheetRequest {
    let course: UUID
    let material: UUID
    var moves: MoveUndo?
}
