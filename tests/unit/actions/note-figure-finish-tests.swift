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

    @Test func brokenXMLIsLeftForTheXMLCheck() throws {
        let done = try NoteFigureFinish.finish("<svg>\n<g>\n</svg>")
        #expect(done.svg == "<svg>\n<g>\n</svg>")
        guard case .notXML? = done.problems.first else {
            Issue.record("not caught")
            return
        }
    }
}
