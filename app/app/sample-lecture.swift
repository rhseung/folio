#if DEBUG && os(macOS)
import AppKit
import CoreText
import PDFKit

/// Debug-only: a slide deck drawn in memory, with a big title on each page, so the lecture reader and the split screen
/// can be seen and tested on a real PDF. The fixtures' `.pdf`s are placeholders PDFKit can't open.
enum SampleLecture {
    static let titles = [
        "Matchings", "Definitions", "Examples", "Maximum matchings", "Alternating paths", "Exercise", "Proof", "Summary",
        "Hall's theorem", "Proof", "Proof (cont.)", "Corollaries", "Marriage problem", "Exercise", "Exercise (cont.)", "Summary",
        "Augmenting paths", "Berge's theorem", "Proof", "Hungarian method", "Example", "Running time", "Exercise", "Summary",
    ]

    /// Chapter pages carry only their title, as a deck's dividers do.
    static let chapters: Set<Int> = [0, 8, 16]

    /// 16:9 pages: the title in large type at the top, then a few body lines.
    static func document(_ titles: [String] = titles) -> PDFDocument? {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 640, height: 360)
        guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
        for (i, title) in titles.enumerated() {
            context.beginPDFPage(nil)
            context.setFillColor(NSColor.white.cgColor)
            context.fill(box)
            draw(title, size: 28, bold: true, at: CGPoint(x: 40, y: 290), in: context)
            for line in 0..<(chapters.contains(i) ? 0 : 3) {
                draw("Slide \(i + 1), point \(line + 1): a line of body text about \(title.lowercased())", size: 14, bold: false,
                     at: CGPoint(x: 40, y: 220 - CGFloat(line) * 28), in: context)
            }
            context.endPDFPage()
        }
        context.closePDF()
        return PDFDocument(data: data as Data)
    }

    static func write(to url: URL) throws {
        guard let data = document()?.dataRepresentation() else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url)
    }

    private static func draw(_ text: String, size: CGFloat, bold: Bool, at point: CGPoint, in context: CGContext) {
        let font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.black]))
        context.textPosition = point
        CTLineDraw(line, context)
    }
}
#endif
