import FolioActions
import FolioDomain
import Foundation
import Testing

struct NoteFigureFinishTests {
    static let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 80">
        <line x1="20" y1="60" x2="200" y2="60" class="s-ink" marker-end="url(#m-ink)"/>
        <text x="20" y="30" class="p-blue">speed $v_0$</text>
        <text x="150" y="30" class="sm">$\\ce{H2O}$</text>
        </svg>
        """

    @Test func mathBecomesGlyphsAndTheStyleGoesIn() throws {
        let done = try NoteFigureFinish.finish(Self.svg)
        #expect(done.problems.isEmpty)
        #expect(done.svg.contains("<style id=\"\(FigureStyle.styleID)\">\(FigureStyle.css)</style>"))
        #expect(done.svg.contains("<defs id=\"\(FigureStyle.defsID)\"><marker id=\"m-ink\""))
        #expect(!done.svg.contains("m-p-red"))
        // 낱말은 글자로 남고 수식은 path가 된다. 원래 `<text>`는 data-source에 남는다.
        #expect(done.svg.contains(">speed </text>"))
        #expect(done.svg.contains("<use href=\"#mj-") && done.svg.contains("<path id=\"mj-"))
        #expect(done.svg.contains("data-source=\"&lt;text x=&quot;20&quot;"))
        #expect(NoteFigure.problems(done.svg).isEmpty)
    }

    @Test func finishingTwiceChangesNothingAndTheSourceComesBack() throws {
        let done = try NoteFigureFinish.finish(Self.svg)
        #expect(try NoteFigureFinish.finish(done.svg).svg == done.svg)
        #expect(try NoteFigureFinish.source(done.svg) == Self.svg)
        #expect(try NoteFigureFinish.source(Self.svg) == Self.svg)
    }

    @Test func labelsThatCollideAreCaught() throws {
        let svg = """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 100">
            <line x1="0" y1="30" x2="200" y2="30" class="s-ink"/>
            <text x="40" y="34">touching label</text>
            <text x="20" y="70">left label</text><text x="30" y="72">overlap label</text>
            <text x="180" y="95">label outside</text>
            </svg>
            """
        let found = try NoteFigureFinish.finish(svg).problems
        #expect(found.contains { if case .onLine = $0 { true } else { false } })
        #expect(found.contains { if case .overlap = $0 { true } else { false } })
        #expect(found.contains { if case .outside = $0 { true } else { false } })
    }

    @Test func aLabelUnderAnOpaqueShapeOrOnTheGridPasses() throws {
        let svg = """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 100">
            <line x1="0" y1="50" x2="200" y2="50" class="s-grid"/>
            <line x1="100" y1="0" x2="100" y2="100" class="s-ink"/>
            <rect x="80" y="36" width="40" height="20" class="paper"/>
            <text x="100" y="52" text-anchor="middle" class="sm">$x$</text>
            </svg>
            """
        #expect(try NoteFigureFinish.finish(svg).problems.isEmpty)
    }

    // 정렬은 `<text>` 자신, 부모 `<g>`, 쓴 사람의 CSS 규칙 어디서 와도 같은 자리에 놓여야 한다. 조각이 부모의 정렬을
    // 물려받으면 낱말만 가운데로 옮겨져 수식과 겹친다.
    @Test func anInheritedAnchorPlacesMixedLabelsLikeItsOwn() throws {
        func figure(_ label: String, style: String = "") -> String {
            """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 80">\(style)
            \(label)
            </svg>
            """
        }
        let own = figure(#"<text x="120" y="40" text-anchor="middle">edge $e$ of weight $w(e)$</text>"#)
        let variants = [
            figure(#"<g text-anchor="middle"><text x="120" y="40">edge $e$ of weight $w(e)$</text></g>"#),
            figure(#"<text x="120" y="40" style="text-anchor: middle">edge $e$ of weight $w(e)$</text>"#),
            figure(
                #"<g class="mid"><text x="120" y="40">edge $e$ of weight $w(e)$</text></g>"#,
                style: "<style>.mid{text-anchor:middle}</style>"),
        ]
        func placed(_ svg: String) throws -> [String] {
            let done = try NoteFigureFinish.finish(svg)
            #expect(done.problems.isEmpty)
            let pieces = /<(?:text|svg) x="([-\d.]+)"/
            return done.svg.matches(of: pieces).map { String($0.output.1) }
        }
        let expected = try placed(own)
        #expect(expected.count == 4)
        for svg in variants { #expect(try placed(svg) == expected) }

        // 굵기도 낱말 폭을 정하므로 어디서 오든 같게 재야 한다. 굵은 글을 보통 굵기로 재면 수식이 낱말에 붙는다.
        let bold = try placed(figure(#"<text x="10" y="40" class="bd">matching $M$ bold</text>"#))
        #expect(bold != (try placed(figure(#"<text x="10" y="40">matching $M$ bold</text>"#))))
        for svg in [
            figure(#"<text x="10" y="40" style="font-weight: bold">matching $M$ bold</text>"#),
            figure(#"<g font-weight="700"><text x="10" y="40">matching $M$ bold</text></g>"#),
            figure(#"<text x="10" y="40" class="heavy">matching $M$ bold</text>"#, style: "<style>.heavy{font-weight:700}</style>"),
        ] { #expect(try placed(svg) == bold) }
    }

    @Test func brokenMathAndMathInTspansAreCaught() throws {
        let svg = """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 300 100">
            <text x="10" y="30">$\\frac{a$</text>
            <text x="10" y="70">sum <tspan class="bd">$n$</tspan></text>
            </svg>
            """
        let found = try NoteFigureFinish.finish(svg).problems
        #expect(found.contains { if case .tex(let tex, _) = $0 { tex == "\\frac{a" } else { false } })
        #expect(found.contains(.tspanMath("sum $n$")))
    }

    @Test func linesMustPassThroughThePointsTheyName() throws {
        // 초점 거리 60, 물체 거리 120인 볼록 렌즈. 평행 광선은 렌즈에서 꺾여 F2(220, 90)를 지난다.
        func lens(_ end: String, through: String = "F2") -> String {
            """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 180">
            <circle id="F2" cx="220" cy="90" r="2.5" class="ink"/>
            <path d="M40 50 L160 50 L\(end)" class="s-p-orange" fill="none" data-through="\(through)"/>
            </svg>
            """
        }
        #expect(try NoteFigureFinish.finish(lens("280 130")).problems.isEmpty)
        #expect(try NoteFigureFinish.finish(lens("270 130")).problems == [.notThrough("path.s-p-orange", "F2", gap: "2.9")])
        #expect(try NoteFigureFinish.finish(lens("280 130", through: "F")).problems == [.noPoint("path.s-p-orange", "F")])
    }

    // 크기가 없는 SVG 이미지는 노트 열 전체 폭으로 늘어난다. 넣은 크기는 viewBox와 같아서 원문으로 되돌릴 때 빠진다.
    @Test func theSizeComesFromTheViewBox() throws {
        let done = try NoteFigureFinish.finish(Self.svg)
        #expect(done.svg.hasPrefix(#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 80" width="240" height="80">"#))
        let half = try NoteFigureFinish.finish(#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 80" width="120"></svg>"#)
        #expect(half.svg.contains(#"width="120" height="40""#))
        let own = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 80" width="100%"><text x="10" y="30">x</text></svg>"#
        let back = try NoteFigureFinish.source(NoteFigureFinish.finish(own).svg)
        #expect(back == own, "\(back)")
    }

    // 코드는 mermaid 도식의 코드처럼 `\texttt` path가 된다. `\texttt`로 쓸 수 없는 글자만 고정폭 글꼴의 글자로 남는다.
    @Test func codeLabelsAreSetInTypewriter() throws {
        let svg = """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 80">
            <text x="10" y="30" class="mono">t1 = y + z</text>
            <g class="mono p-blue"><text x="10" y="60">x ^ 2</text></g>
            </svg>
            """
        let done = try NoteFigureFinish.finish(svg)
        #expect(done.problems.isEmpty)
        #expect(done.svg.contains(".mono{font-family:\(FigureStyle.Font.monoFamily)}"))
        #expect(!done.svg.contains(">t1 = y + z</text>") && done.svg.contains("<path id=\"mj-"))
        #expect(done.svg.contains(#"class="p-blue">"#))
        #expect(done.svg.contains(">^</text>"))
        #expect(try NoteFigureFinish.source(done.svg) == svg)
    }

    // 글꼴과 글자색은 루트에서 물려받으므로 `<g>`의 클래스가 그 아래 글자에 닿는다. 수식 조각도 부모의 색을 받는다.
    @Test func groupClassesReachTheirLabels() throws {
        let css = FigureStyle.css
        #expect(!css.contains("text{"))
        #expect(css.hasPrefix("svg{font-family:") && css.contains("svg{fill:#000000}"))
        let svg = """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 80">
            <g class="p-red sm"><text x="10" y="30">$v_1$ cut</text></g>
            </svg>
            """
        let done = try NoteFigureFinish.finish(svg)
        #expect(done.problems.isEmpty)
        #expect(done.svg.contains(#"<g class="p-red">"#))
    }

    // 칸 하나에 든 것은 그 칸의 테두리 안에 있어야 한다. 칸 사이를 잇는 선은 두 칸에 걸쳐도 된다.
    @Test func contentThatLeavesItsCellIsCaught() throws {
        func cells(_ inside: String) -> String {
            """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 120">
            <rect x="10" y="10" width="140" height="100" class="s-ink" fill="none" stroke-width="1.1"/>
            <rect x="170" y="10" width="140" height="100" class="s-ink" fill="none" stroke-width="1.1"/>
            <line x1="150" y1="60" x2="170" y2="60" class="s-ink" marker-end="url(#m-ink)"/>
            \(inside)
            </svg>
            """
        }
        #expect(try NoteFigureFinish.finish(cells(#"<circle cx="80" cy="60" r="12" class="paper s-ink"/>"#)).problems.isEmpty)
        let found = try NoteFigureFinish.finish(cells(#"<circle cx="140" cy="60" r="16" class="paper s-ink"/>"#)).problems
        #expect(found.contains { if case .outOfCell(let item, _) = $0 { item.hasPrefix("circle.paper.s-ink") } else { false } })
        let curve = try NoteFigureFinish.finish(cells(#"<path d="M40 100 Q80 140 120 100" class="s-ink" fill="none"/>"#)).problems
        #expect(curve.contains { if case .outOfCell(let item, _) = $0 { item.hasPrefix("path.s-ink") } else { false } })
    }

    // 정점 가까이에서 끝나는 변은 경계나 중심에 닿아야 한다. 뒤에 그린 불투명한 정점이 가린 끝은 경계에서 끝난 것이다.
    @Test func edgesThatStopShortOfAVertexAreCaught() throws {
        func graph(_ edge: String, vertexFirst: Bool = false) -> String {
            let vertices = #"<circle cx="40" cy="40" r="10" class="paper s-ink"/><circle cx="140" cy="40" r="10" class="paper s-ink"/>"#
            return """
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 180 80">
                \(vertexFirst ? vertices + edge : edge + vertices)
                </svg>
                """
        }
        #expect(try NoteFigureFinish.finish(graph(#"<line x1="40" y1="40" x2="140" y2="40" class="s-ink"/>"#)).problems.isEmpty)
        #expect(try NoteFigureFinish.finish(graph(#"<line x1="50" y1="40" x2="130" y2="40" class="s-ink"/>"#)).problems.isEmpty)
        #expect(try NoteFigureFinish.finish(graph(#"<line x1="44" y1="40" x2="136" y2="40" class="s-ink"/>"#)).problems.isEmpty)
        let short = try NoteFigureFinish.finish(graph(#"<line x1="50" y1="40" x2="125" y2="40" class="s-ink"/>"#)).problems
        #expect(short == [.looseEnd("line.s-ink @(125, 40)", "circle.paper.s-ink @(140, 40)", gap: "5.0")])
        // 정점을 먼저 그리면 정점 안으로 들어간 변이 보인다.
        let into = try NoteFigureFinish.finish(graph(#"<line x1="44" y1="40" x2="130" y2="40" class="s-ink"/>"#, vertexFirst: true))
            .problems
        #expect(into == [.looseEnd("line.s-ink @(44, 40)", "circle.paper.s-ink @(40, 40)", gap: "6.0")])
    }

    @Test func nestedSourcesAreUnfoldedBeforeTheCheck() throws {
        let svg = """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 20"><g data-source="&lt;g data-source=&quot;&amp;lt;script&amp;gt;x()&amp;lt;/script&amp;gt;&quot;/&gt;"/></svg>
            """
        #expect(try NoteFigureFinish.source(svg).contains("<script>x()</script>"))
        #expect(try NoteFigureFinish.finish(svg).problems.contains { if case .script = $0 { true } else { false } })
    }

    @Test func brokenXMLIsLeftForTheXMLCheck() throws {
        let done = try NoteFigureFinish.finish("<svg>\n<g>\n</svg>")
        #expect(done.svg == "<svg>\n<g>\n</svg>")
        guard case .notXML? = done.problems.first else {
            Issue.record("not caught")
            return
        }
    }
}
