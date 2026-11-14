import FolioAI
import FolioDomain
import FolioStorage
import Foundation
import PDFKit

enum LectureSource: Equatable, Sendable {
    case outline, titles, claude
}
