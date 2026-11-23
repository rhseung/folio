import FolioActions
import FolioDomain
import Foundation
import Testing

struct NoteFigureFinishTests {
    static let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 80">
        <line x1="20" y1="60" x2="200" y2="60" class="s-ink" marker-end="url(#m-ink)"/>
        <text x="20" y="30" class="p-blue">속도 $v_0$</text>
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
        #expect(done.svg.contains(">속도 </text>"))
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
            <text x="40" y="34">닿는 라벨</text>
            <text x="20" y="70">왼쪽 라벨</text><text x="30" y="72">겹친 라벨</text>
            <text x="180" y="95">밖으로 나간 라벨</text>
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
        let own = figure(#"<text x="120" y="40" text-anchor="middle">간선 $e$ 의 무게 $w(e)$</text>"#)
        let variants = [
            figure(#"<g text-anchor="middle"><text x="120" y="40">간선 $e$ 의 무게 $w(e)$</text></g>"#),
            figure(#"<text x="120" y="40" style="text-anchor: middle">간선 $e$ 의 무게 $w(e)$</text>"#),
            figure(#"<g class="mid"><text x="120" y="40">간선 $e$ 의 무게 $w(e)$</text></g>"#, style: "<style>.mid{text-anchor:middle}</style>"),
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
        let bold = try placed(figure(#"<text x="10" y="40" class="bd">matching $M$ 굵게</text>"#))
        #expect(bold != (try placed(figure(#"<text x="10" y="40">matching $M$ 굵게</text>"#))))
        for svg in [
            figure(#"<text x="10" y="40" style="font-weight: bold">matching $M$ 굵게</text>"#),
            figure(#"<g font-weight="700"><text x="10" y="40">matching $M$ 굵게</text></g>"#),
            figure(#"<text x="10" y="40" class="heavy">matching $M$ 굵게</text>"#, style: "<style>.heavy{font-weight:700}</style>"),
        ] { #expect(try placed(svg) == bold) }
    }

    @Test func brokenMathAndMathInTspansAreCaught() throws {
        let svg = """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 300 100">
            <text x="10" y="30">$\\frac{a$</text>
            <text x="10" y="70">합 <tspan class="bd">$n$</tspan></text>
            </svg>
            """
        let found = try NoteFigureFinish.finish(svg).problems
        #expect(found.contains { if case .tex(let tex, _) = $0 { tex == "\\frac{a" } else { false } })
        #expect(found.contains(.tspanMath("합 $n$")))
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
