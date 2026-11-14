import FolioStorage
import Foundation

enum Exit: Int32 {
    case success = 0, unexpected = 1, usage = 2, notFound = 3, rule = 4, needsConfirmation = 5, conflict = 6, coverage = 7

    var code: String {
        switch self {
        case .success: "success"
        case .unexpected: "unexpected"
        case .usage: "usage"
        case .notFound: "not_found"
        case .rule: "rule"
        case .needsConfirmation: "needs_confirmation"
        case .conflict: "conflict"
        case .coverage: "coverage"
        }
    }
}
