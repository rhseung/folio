import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Observation

struct SolveRequest: Equatable {
    var id = UUID()
    var scope: QuizScope
    var label: String
    var order: QuizOrder = .unitOrder
}
