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
        draw([.bold("2024 Midterm")], size: 17, at: CGPoint(x: 72, y: 730), in: context)
        draw(
            [.roman("1. (10 pts) Is the graph "), .math("K"), .sub("3,3"), .roman(" below planar? Answer true or false.")], size: 11,
            at: CGPoint(x: 72, y: 690), in: context)
        let top = [0, 1, 2].map { CGPoint(x: planar.minX + 50 + CGFloat($0) * 80, y: planar.maxY - 40) }
        let bottom = [0, 1, 2].map { CGPoint(x: planar.minX + 50 + CGFloat($0) * 80, y: planar.minY + 40) }
        graph(
            top + bottom, edges: top.indices.flatMap { i in bottom.indices.map { (i, 3 + $0) } },
            labels: ["u", "u", "u", "v", "v", "v"], sides: [.above, .above, .above, .below, .below, .below], in: context)
        context.endPDFPage()

        begin()
        draw([.roman("2. Let "), .math("G"), .roman(" be the bipartite graph below.")], size: 11, at: CGPoint(x: 72, y: 730), in: context)
        let left = [0, 1, 2].map { CGPoint(x: bipartite.minX + 70, y: bipartite.maxY - 40 - CGFloat($0) * 60) }
        let right = [0, 1, 2].map { CGPoint(x: bipartite.maxX - 70, y: bipartite.maxY - 40 - CGFloat($0) * 60) }
        graph(
            left + right, edges: [(0, 3), (0, 4), (1, 3), (2, 4), (2, 5)], labels: ["a", "a", "a", "b", "b", "b"],
            sides: [.left, .left, .left, .right, .right, .right], in: context)
        draw([.roman("(a) (5 pts) State Hall\u{2019}s theorem.")], size: 11, at: CGPoint(x: 72, y: 460), in: context)
        draw(
            [.roman("(b) (5 pts) Use it to decide whether "), .math("G"), .roman(" has a perfect matching.")], size: 11,
            at: CGPoint(x: 72, y: 436), in: context)
        context.endPDFPage()

        begin()
        draw([.roman("3. Find the chromatic number of the Petersen graph.")], size: 11, at: CGPoint(x: 72, y: 730), in: context)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    public static func write(to url: URL) throws {
        try data().write(to: url)
    }

    // 글자 하나의 모양이다. 문제지는 LaTeX로 짠 것처럼 Computer Modern(KaTeX 글꼴)으로 쓰고, 수식은 이탤릭, 아래 첨자는 작은
    // 로만체다. 노트 그림의 스타일(`FigureStyle`)과 같다.
    enum Run {
        case roman(String), bold(String), math(String), sub(String)

        var text: String {
            switch self {
            case .roman(let t), .bold(let t), .math(let t), .sub(let t): t
            }
        }

        var face: String {
            switch self {
            case .roman, .sub: "KaTeX_Main-Regular"
            case .bold: "KaTeX_Main-Bold"
            case .math: "KaTeX_Main-Italic"
            }
        }

        // 아래 첨자는 본문의 0.7배 크기로 기준선 아래 0.15배에 둔다.
        var scale: CGFloat { if case .sub = self { 0.7 } else { 1 } }
        var rise: CGFloat { if case .sub = self { -0.15 } else { 0 } }
    }

    enum Side { case above, below, left, right }

    // 꼭짓점은 작은 점이고 이름은 선과 겹치지 않게 그래프 바깥쪽에 둔다. 선 굵기는 노트 그림의 선(`FigureStyle.lineWidth`)이다.
    private static func graph(_ points: [CGPoint], edges: [(Int, Int)], labels: [String], sides: [Side], in context: CGContext) {
        context.setStrokeColor(CGColor(gray: 0, alpha: 1))
        context.setLineWidth(FigureStyle.lineWidth)
        context.setLineCap(.round)
        for (a, b) in edges {
            context.move(to: points[a])
            context.addLine(to: points[b])
        }
        context.strokePath()
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        let size = 11 * FigureStyle.Font.mathScale
        var counts: [String: Int] = [:]
        for (i, point) in points.enumerated() {
            context.fillEllipse(in: CGRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5))
            counts[labels[i], default: 0] += 1
            let runs: [Run] = [.math(labels[i]), .sub(String(counts[labels[i]] ?? 1))]
            let width = self.width(runs, size: size)
            let at: CGPoint =
                switch sides[i] {
                case .above: CGPoint(x: point.x - width / 2, y: point.y + 8)
                case .below: CGPoint(x: point.x - width / 2, y: point.y - 8 - size * 0.7)
                case .left: CGPoint(x: point.x - 8 - width, y: point.y - size * 0.3)
                case .right: CGPoint(x: point.x + 8, y: point.y - size * 0.3)
                }
            draw(runs, size: size, at: at, in: context)
        }
    }

    private static func line(_ runs: [Run], size: CGFloat) -> [(CTLine, CGFloat)] {
        runs.map { run in
            let font = Fonts.font(run.face, size: size * run.scale)
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
            ]
            return (CTLineCreateWithAttributedString(NSAttributedString(string: run.text, attributes: attributes)), run.rise * size)
        }
    }

    private static func width(_ runs: [Run], size: CGFloat) -> CGFloat {
        line(runs, size: size).reduce(0) { $0 + CGFloat(CTLineGetTypographicBounds($1.0, nil, nil, nil)) }
    }

    private static func draw(_ runs: [Run], size: CGFloat, at point: CGPoint, in context: CGContext) {
        var x = point.x
        for (line, rise) in line(runs, size: size) {
            context.textPosition = CGPoint(x: x, y: point.y + rise)
            CTLineDraw(line, context)
            x += CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        }
    }

    // KaTeX 글꼴은 앱 묶음에 있다. 픽스처를 쓰는 명령줄 도구와 테스트에는 앱 묶음이 없어서 저장소의 같은 파일을 읽는다. 둘 다
    // 없으면 Times로 그린다.
    private enum Fonts {
        static let registered: Bool = {
            let repo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let urls = ["regular", "italic", "bold"].compactMap { name -> URL? in
                if let url = Bundle.main.url(forResource: "katex-main-\(name)", withExtension: "ttf") { return url }
                let url = repo.appending(path: "app/resources/fonts/katex-main-\(name).ttf")
                return FileManager.default.fileExists(atPath: url.path) ? url : nil
            }
            for url in urls { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
            return urls.count == 3
        }()

        static func font(_ name: String, size: CGFloat) -> CTFont {
            let fallback = name.hasSuffix("Italic") ? "Times-Italic" : name.hasSuffix("Bold") ? "Times-Bold" : "Times-Roman"
            return CTFontCreateWithName((registered ? name : fallback) as CFString, size, nil)
        }
    }
}
