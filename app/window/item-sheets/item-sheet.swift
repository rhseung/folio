import FolioDomain
import FolioStorage
import SwiftUI

enum ItemSheet: Identifiable {
    case session(SessionSheetRequest)
    case exam(course: UUID, exam: UUID)
    case assignment(course: UUID, assignment: UUID)
    case review(course: UUID, unit: UUID)
    case card(course: UUID, draft: CardDraft)
    case generateCards(course: UUID, unit: UUID)
    case note(NoteSheetRequest)
    case noteFolder(NoteSheetRequest)
    case material(MaterialSheetRequest)
    case course(UUID)

    var id: UUID {
        switch self {
        case .session(let request): request.id
        case .exam(_, let id), .assignment(_, let id), .review(_, let id), .generateCards(_, let id): id
        case .card(_, let draft): draft.id
        case .note(let request), .noteFolder(let request): request.id
        case .material(let request): request.material
        case .course(let id): id
        }
    }
}
