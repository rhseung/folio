import FolioDomain
import FolioStorage
import SwiftUI

enum ItemSheet: Identifiable {
    case session(SessionSheetRequest)
    case exam(course: UUID, exam: UUID)
    case assignment(course: UUID, assignment: UUID)
    case card(course: UUID, draft: CardDraft)
    case suggestCards(course: UUID, unit: UUID)
    case flipCards(course: UUID, unit: UUID?)
    // `count`가 있으면 그 개수를 먼저 고른다. 문제 부족 줄은 최소 문제 수까지 모자란 개수를 준다.
    case makeProblems(course: UUID, unit: UUID, count: Int? = nil)
    case solve(SolveRequest)
    case problemSet(course: UUID)
    case problem(course: UUID, set: UUID, problem: UUID)
    case note(NoteSheetRequest)
    case noteFolder(NoteSheetRequest)
    case material(MaterialSheetRequest)
    case course(UUID)

    var id: UUID {
        switch self {
        case .session(let request): request.id
        case .exam(_, let id), .assignment(_, let id), .suggestCards(_, let id), .makeProblems(_, let id, _): id
        case .flipCards(let course, let unit): unit ?? course
        case .solve(let request): request.id
        case .problemSet(let course): course
        case .problem(_, _, let id): id
        case .card(_, let draft): draft.id
        case .note(let request), .noteFolder(let request): request.id
        case .material(let request): request.material
        case .course(let id): id
        }
    }
}
