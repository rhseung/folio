import CoreGraphics
import CoreText
import Foundation

// 픽스처의 다른 `.pdf`는 PDFKit이 열지 못하는 자리표시자이므로, 렉처 읽기와 나누기 화면이 읽을 실제 PDF를 메모리에서
// 그린다. Mac과 iPad에서 같게 그리도록 CoreGraphics와 CoreText만 쓴다.
public enum SampleLecture {
    public static let titles = [
        "Matchings", "Definitions", "Examples", "Maximum matchings", "Alternating paths", "Exercise", "Proof", "Summary",
        "Hall's theorem", "Proof", "Proof (cont.)", "Corollaries", "Marriage problem", "Exercise", "Exercise (cont.)", "Summary",
        "Augmenting paths and Berge's theorem in simple bipartite graphs", "Berge's theorem", "Proof", "Hungarian method", "Example",
        "Running time", "Exercise", "Summary",
    ]

    public static let chapters: Set<Int> = [0, 8, 16]

    public static func data(_ titles: [String] = titles) -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 960, height: 540)
        guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            return Data()
        }
        for (i, title) in titles.enumerated() {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(box)
            draw(title, size: 24, bold: true, at: CGPoint(x: 48, y: 460), in: context)
            for line in 0..<(chapters.contains(i) ? 0 : 3) {
                draw(
                    "Slide \(i + 1), point \(line + 1): a line of body text about \(title.lowercased())", size: 14, bold: false,
                    at: CGPoint(x: 48, y: 380 - CGFloat(line) * 28), in: context)
            }
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    public static func write(to url: URL) throws {
        try data().write(to: url)
    }

    private static func draw(_ text: String, size: CGFloat, bold: Bool, at point: CGPoint, in context: CGContext) {
        let font =
            CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        context.textPosition = point
        CTLineDraw(line, context)
    }
}
