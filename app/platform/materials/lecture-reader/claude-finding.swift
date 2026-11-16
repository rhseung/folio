import FolioAI
import FolioDomain
import FolioStorage
import Foundation
import PDFKit

enum ClaudeFinding: Equatable, Sendable {
    case found(LectureSplit)
    case nothing
    case unreadable
    case failed(String)

    var message: String? {
        switch self {
        case .found: nil
        case .nothing: String(localized: .lectureClaudeNothing)
        case .unreadable: String(localized: .lectureClaudeUnreadable)
        case .failed(let why): String(localized: .lectureClaudeFailed(why))
        }
    }
}
