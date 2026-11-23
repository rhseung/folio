import Foundation

// 노트 그림(SVG), 위젯, mermaid 도식이 함께 읽는 그림 스타일 표다. 어느 AI가 그려도 위키백과나 LaTeX 교과서의 그림처럼
// 같은 모양이 되게 한다. 그림은 이미지로 보여서 페이지 CSS를 읽지 못하므로, 쓸 때 이 표의 `<style>`과 화살촉을 그림에
// 넣는다(NoteFigureFinish). 위젯과 노트 페이지는 같은 값을 CSS 변수로 받는다.
public enum FigureStyle {
    public struct Ink: Hashable, Sendable {
        public let name: String
        public let light: String
        public let dark: String

        public var fill: String { name }
        public var stroke: String { "s-" + name }
    }

    // 선과 글자는 검정, 강조는 원색이다. 다크에서 검정은 종이색으로 바뀐다. 다크의 원색은 같은 색조에서 밝기를 올리고
    // OKLCH 채도(chroma)를 70%로 낮춘 값이다. 넓게 칠한 면이 다크 바탕에서 튀지 않게 하려는 것이다. paper는 노트 카드색이다.
    public static let inks: [Ink] = [
        Ink(name: "ink", light: "#000000", dark: "#E6E2DB"),
        Ink(name: "muted", light: "#6B6B6B", dark: "#A29D95"),
        Ink(name: "grid", light: "#D0D0D0", dark: "#45423E"),
        Ink(name: "paper", light: "#FFFFFF", dark: "#272624"),
        Ink(name: "p-blue", light: "#1A2FFF", dark: "#798CDF"),
        Ink(name: "p-red", light: "#E8141C", dark: "#E57468"),
        Ink(name: "p-green", light: "#00A53C", dark: "#71CA8B"),
        Ink(name: "p-orange", light: "#FF8A00", dark: "#ECAE70"),
        Ink(name: "p-magenta", light: "#D417C8", dark: "#DA77D0"),
        Ink(name: "p-cyan", light: "#00A3D1", dark: "#75CBE4"),
    ]

    public static let ink = inks[0]
    public static let paper = inks[3]
    public static let grid = inks[2]

    // 선 굵기는 표의 역할로 고른다. 화살촉이 선 굵기를 따라 커지므로 굵은 선의 촉은 저절로 커진다.
    public static let strokes: [(role: String, width: Double)] = [
        ("hair", 0.9), ("box", 1.1), ("line", lineWidth), ("curve", 1.7), ("bold", 2.6),
    ]
    public static let lineWidth = 1.3

    // TikZ `stealth`처럼 뒤가 조금 오목한 촉이다. 크기는 선 굵기의 배수다. 표의 촉보다 이만큼 넘게 크면 쓰지 않는다.
    public static let arrow = (length: 5.75, width: 4.3, notch: 1.15)
    static let arrowSlack = 1.25

    public enum Font {
        public static let sans = #"-apple-system,"SF Pro Text","Helvetica Neue","Apple SD Gothic Neo",sans-serif"#
        public static let size = 14.0
        // 클래스 이름과 글자 크기다. 노트 열이 좁아져도 읽히는 가장 작은 크기가 12px다.
        public static let sizes: [(name: String, size: Double)] = [("sm", 12), ("lg", 17)]
        public static let bold = "bd"
        // 코드 라벨의 클래스다. 쓸 때 낱말을 LaTeX 타자기체(`\texttt`) path로 바꾸고, `\texttt`로 쓸 수 없는 글자만
        // 이 글꼴로 둔다. mermaid 도식의 코드와 같은 모양이다.
        public static let mono = "mono"
        public static let monoFamily = #"ui-monospace,"SF Mono",Menlo,monospace"#
        // KaTeX가 수식을 본문의 1.21배로 그리는 것과 같은 비율이다. Computer Modern의 x-height가 SF보다 작아서 이만큼
        // 키워야 낱말과 높이가 맞는다.
        public static let mathScale = 1.21
        // LaTeX 타자기체(\texttt) 한 글자의 폭(em)이다.
        public static let monoEm = 0.525
    }

    // 그림 안의 글은 라벨만 둔다. 설명 문단은 노트 본문이 맡는다. 수식 하나는 한 글자로 센다.
    public static let labelLimit = 32
    // 글자로만 된 두 글자 이상의 낱말이 이만큼 있으면 라벨이 아니라 문장이다. 정점·집합 이름, 축, 짧은 태그("augmenting path",
    // "back edge to ancestor")는 네 낱말 안에 든다. 한 글자 변수, 숫자가 든 이름(`t1`), 기호는 세지 않아서
    // 코드 줄(`t1 = y + z`)은 걸리지 않는다. 코드 클래스(`mono`)의 라벨은 세지 않는다.
    public static let proseWords = 5

    // 쓸 때 넣는 `<style>`과 `<defs>`의 id다. 고쳐 쓸 때 이 id로 찾아 걷어 내고 다시 넣는다. 그림 엔진(figure.js)도
    // 같은 id를 쓴다.
    public static let styleID = "folio-figure"
    public static let defsID = "folio-figure-defs"

    public static func markerID(_ ink: Ink) -> String { "m-" + ink.name }

    // viewBox 한 칸이 선 굵기의 0.5배가 되게 두 배로 잡는다. refX를 촉 끝보다 조금 안쪽에 둬서 둥근 선 끝이 촉 밖으로
    // 나오지 않는다.
    public static func marker(_ ink: Ink) -> String { marker(ink, paint: "class=\"\(ink.fill)\"") }

    static func marker(_ ink: Ink, paint: String) -> String {
        let (l, w, n) = (arrow.length * 2, arrow.width * 2, arrow.notch * 2)
        return "<marker id=\"\(markerID(ink))\" viewBox=\"0 0 \(g(l)) \(g(w))\" refX=\"\(g(l - 1.6))\" refY=\"\(g(w / 2))\" "
            + "markerWidth=\"\(g(arrow.length))\" markerHeight=\"\(g(arrow.width))\" markerUnits=\"strokeWidth\" orient=\"auto-start-reverse\">"
            + "<path d=\"M0,0 L\(g(l)),\(g(w / 2)) L0,\(g(w)) L\(g(n)),\(g(w / 2)) z\" \(paint)/></marker>"
    }

    // 위젯 frame에 넣는 촉이다. 위젯의 클래스와 섞이는 문서라 `.ink` 같은 클래스 규칙을 넣지 않고 `variables`의 변수로
    // 칠한다. `display:none`인 SVG 안의 참조 대상을 그리지 않는 브라우저가 있어서 크기 0인 SVG에 둔다. 크기는
    // 위젯의 `svg { width: 100% }` 같은 규칙이 이기지 못하게 인라인 style로 정한다.
    public static let markersID = "folio-figure-markers"
    public static let widgetMarkers: String =
        "<svg id=\"\(markersID)\" aria-hidden=\"true\" focusable=\"false\" "
        + "style=\"position:absolute;width:0;height:0;overflow:hidden;pointer-events:none\"><defs>"
        + inks.map { marker($0, paint: "style=\"fill:var(--\($0.name))\"") }.joined() + "</defs></svg>"

    // 그림의 `<style>` 내용이다. 글꼴과 글자색은 루트 `svg`에 두어 물려받게 한다. `text{…}`처럼 글자에 바로 걸면
    // `<g class="p-blue">`나 `<g class="sm">` 아래의 글자가 그 클래스를 물려받지 못한다. 루트의 fill은 class 없는 글자와
    // 면이 다크에서 사라지지 않게 하는 기본색이다.
    public static let css: String = {
        let fonts =
            "svg{font-family:\(Font.sans);font-size:\(g(Font.size))px}"
            + Font.sizes.map { ".\($0.name){font-size:\(g($0.size))px}" }.joined() + ".\(Font.bold){font-weight:700}"
            + ".\(Font.mono){font-family:\(Font.monoFamily)}"
        func colors(_ pick: (Ink) -> String) -> String {
            "svg{fill:\(pick(ink))}" + inks.map { ".\($0.fill){fill:\(pick($0))}.\($0.stroke){stroke:\(pick($0))}" }.joined()
        }
        return fonts + colors(\.light) + "@media (prefers-color-scheme: dark){\(colors(\.dark))}"
    }()

    // 위젯과 노트 페이지(mermaid)가 받는 변수다. class 이름 앞에 `--`를 붙인 이름이다(`.p-blue` → `var(--p-blue)`).
    public static let variables: String = {
        func colors(_ pick: (Ink) -> String) -> String { inks.map { "--\($0.name):\(pick($0));" }.joined() }
        let shape =
            "--figure-arrow-length:\(g(arrow.length));--figure-arrow-width:\(g(arrow.width));--figure-arrow-notch:\(g(arrow.notch));"
            + "--figure-math-scale:\(g(Font.mathScale));--figure-mono-em:\(g(Font.monoEm));--figure-sans:\(Font.sans);"
        return ":root{\(colors(\.light))\(shape)}@media (prefers-color-scheme: dark){:root{\(colors(\.dark))}}"
    }()

    // 그림 엔진(sources/web/src/figure.js)이 받는 표다.
    public static let engineJSON: String = {
        struct Table: Encodable {
            var css: String
            var markers: [String: String]
            var fills: [String]
            var strokes: [String]
            var paper: String
            var grid: String
            var ink: String
            var bold: String
            var mono: String
            var sizes: [String: Double]
            var mathScale: Double
            var monoEm: Double
        }
        let table = Table(
            css: css, markers: Dictionary(uniqueKeysWithValues: inks.map { (markerID($0), marker($0)) }), fills: inks.map(\.fill),
            strokes: inks.map(\.stroke), paper: paper.fill, grid: grid.stroke, ink: ink.fill, bold: Font.bold, mono: Font.mono,
            sizes: Dictionary(uniqueKeysWithValues: [("", Font.size)] + Font.sizes.map { ($0.name, $0.size) }), mathScale: Font.mathScale,
            monoEm: Font.monoEm)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(table)).flatMap { String(bytes: $0, encoding: .utf8) } ?? "{}"
    }()

    static func g(_ value: Double) -> String { String(format: "%g", value) }
}
