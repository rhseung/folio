import FolioAI
import FolioDomain
import FolioStorage
import Foundation
import PDFKit

enum LectureFinding: Equatable, Sendable {
    case found(LectureSplit, LectureSource)
    case nothing(pageCount: Int)
    case unreadable
    case failed(String, pageCount: Int)
}
