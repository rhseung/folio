import CoreGraphics
import CoreText
import FolioDomain
import Foundation

// 문제 뽑기의 검토 시트와 풀기 화면이 잘라 보일 그림이 있는 문제지다. 픽스처의 다른 `.pdf`는 PDFKit이 열지 못하는
// 자리표시자라서 그림 칸을 확인할 수 없다. 1번은 자기 그림(K₃,₃)을, 2번의 두 소문제는 지문의 그림(이분 그래프)을 함께 본다.
// `SampleLecture`처럼 CoreGraphics와 CoreText만 쓴다.
public enum SampleSheet {
    static let page = CGSize(width: 612, height: 792)
    // 그림을 그리는 칸이다. CoreGraphics의 왼쪽 아래 기준 좌표이고, 시나리오의 초안은 이 칸을 `region(_:)`으로 바꿔 쓴다.
    static let planar = CGRect(x: 72, y: 470, width: 260, height: 190)
    static let bipartite = CGRect(x: 72, y: 500, width: 280, height: 200)

    public static var planarFigure: ProblemRegion? { region(planar, page: 1) }
    public static var bipartiteFigure: ProblemRegion? { region(bipartite, page: 2) }

    static func region(_ rect: CGRect, page number: Int) -> ProblemRegion? {
        ProblemRegion(
            page: number, x: rect.minX / page.width, y: 1 - rect.maxY / page.height, width: rect.width / page.width,
            height: rect.height / page.height)
    }

    public static func data() -> Data {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: page)
        guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            return Data()
        }
        func begin() {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(box)
        }
        begin()
        draw("2024 Midterm", size: 20, bold: true, at: CGPoint(x: 72, y: 730), in: context)
        draw(
            "1. (10 pts) Is the graph K3,3 below planar? Answer true or false.", size: 12, bold: false, at: CGPoint(x: 72, y: 690),
            in: context)
        let top = [0, 1, 2].map { CGPoint(x: planar.minX + 50 + CGFloat($0) * 80, y: planar.maxY - 30) }
        let bottom = [0, 1, 2].map { CGPoint(x: planar.minX + 50 + CGFloat($0) * 80, y: planar.minY + 30) }
        graph(
            top + bottom, edges: top.indices.flatMap { i in bottom.indices.map { (i, 3 + $0) } },
            labels: ["u1", "u2", "u3", "v1", "v2", "v3"], in: context)
        context.endPDFPage()

        begin()
        draw("2. Let G be the bipartite graph below.", size: 12, bold: false, at: CGPoint(x: 72, y: 730), in: context)
        let left = [0, 1, 2].map { CGPoint(x: bipartite.minX + 50, y: bipartite.maxY - 30 - CGFloat($0) * 70) }
        let right = [0, 1, 2].map { CGPoint(x: bipartite.maxX - 50, y: bipartite.maxY - 30 - CGFloat($0) * 70) }
        graph(left + right, edges: [(0, 3), (0, 4), (1, 3), (2, 4), (2, 5)], labels: ["a1", "a2", "a3", "b1", "b2", "b3"], in: context)
        draw("(a) (5 pts) State Hall's theorem.", size: 12, bold: false, at: CGPoint(x: 72, y: 460), in: context)
        draw(
            "(b) (5 pts) Use it to decide whether G has a perfect matching.", size: 12, bold: false, at: CGPoint(x: 72, y: 430), in: context
        )
        context.endPDFPage()

        begin()
        draw("3. Find the chromatic number of the Petersen graph.", size: 12, bold: false, at: CGPoint(x: 72, y: 730), in: context)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    public static func write(to url: URL) throws {
        try data().write(to: url)
    }

    private static func graph(_ points: [CGPoint], edges: [(Int, Int)], labels: [String], in context: CGContext) {
        context.setStrokeColor(CGColor(gray: 0, alpha: 1))
        context.setLineWidth(1)
        for (a, b) in edges {
            context.move(to: points[a])
            context.addLine(to: points[b])
        }
        context.strokePath()
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        for (point, label) in zip(points, labels) {
            context.fillEllipse(in: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8))
            draw(label, size: 11, bold: false, at: CGPoint(x: point.x + 8, y: point.y + 6), in: context)
        }
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
