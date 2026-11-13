#if os(iOS)
import PDFKit
import Testing
import UIKit
@testable import Folio

// UIKit은 `init(frame:)` 안에서 뷰의 frame을 정한다. `SteadyPDFView`가 그 자리에서 PDFKit이 아직 만들지 않은 PDF 뷰의 `document`를 읽어서, iPad가 여는
// 모든 PDF에서 앱이 충돌했다.
@MainActor
struct PDFPadTests {
    @Test func opensAPDFAndKeepsItAcrossWidths() throws {
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { context in
            for _ in 0..<3 { context.beginPage() }
        }
        let document = try #require(PDFDocument(data: data))
        let controller = PDFController(document: document, page: 1)
        for width: CGFloat in [400, 320, 900] {
            controller.view.frame = CGRect(x: 0, y: 0, width: width, height: 600)
            controller.view.layoutIfNeeded()
        }
        #expect(controller.view.document === document)
    }
}
#endif
