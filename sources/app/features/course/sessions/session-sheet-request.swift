import FolioActions
import FolioDomain
import Foundation
import Observation

struct SessionSheetRequest: Identifiable {
    let id = UUID()
    let course: UUID
    var session: UUID?
    var start: Date?
    var focus: SessionSection?
    var viewed: [SessionMaterial] = []
    var recorded = false
    var asked = false
}
