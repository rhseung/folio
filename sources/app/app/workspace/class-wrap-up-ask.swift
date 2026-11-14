import FolioDomain
import Foundation
import PDFKit

struct ClassWrapUpAsk: Identifiable, Equatable {
    let id = UUID()
    let course: UUID
    let session: UUID
    let viewed: [SessionMaterial]
}
