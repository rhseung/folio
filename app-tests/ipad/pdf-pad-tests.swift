#if os(iOS)
import PDFKit
import Testing
import UIKit
@testable import Folio

/// UIKit sets a view's frame from inside `init(frame:)`, and `SteadyPDFView` read the PDF view's `document` there, before
/// PDFKit had made it: every PDF the iPad opened crashed the app.
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
