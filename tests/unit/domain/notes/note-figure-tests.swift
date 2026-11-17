import FolioCore
import FolioDomain
import Foundation
import Testing

struct NoteFigureTests {
    static let good = """
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 100 40">
        <defs><marker id="arrow" markerWidth="6" markerHeight="4"><path d="M0 0L4 2L0 4z"/></marker></defs>
        <path class="s-ink" fill="none" d="M0 0L10 10" marker-end="url(#m-ink)"/><use xlink:href="#arrow"/>
        <image href="data:image/png;base64,iVBORw0KGgo="/><text class="p-blue" x="4" y="20">매칭 $M$</text>
        <rect style="fill:none;stroke-width:1.3" class="s-p-red" width="10" height="10"/>
        </svg>
        """

    @Test func namesLandRightInAssets() {
        #expect(NoteFigure.fileName("graph") == "graph.svg")
        #expect(NoteFigure.fileName(" graph.SVG ") == "graph.SVG")
        #expect(NoteFigure.fileName("assets/graph.svg") == "graph.svg")
        #expect(NoteFigure.fileName("Notes/assets/증가 경로.svg") == "증가 경로.svg")
        #expect(NoteFigure.fileName("Fig 1.2") == "Fig 1.2.svg")
        for bad in ["", ".svg", ".hidden", "a/b.svg", "../a.svg", "a\\b", "graph.png", "scan.pdf"] {
            #expect(NoteFigure.fileName(bad) == nil, "\(bad)")
        }
        #expect(NoteFigure.path("graph.svg") == "Notes/assets/graph.svg")
    }

    @Test func aFigureInTheStyleClassesPasses() {
        #expect(NoteFigure.problems(Self.good).isEmpty)
    }

    @Test func paintedColorsAreCaught() {
        let svg = """
            <svg xmlns="http://www.w3.org/2000/svg"><style>.a{fill:#222} .b{ stroke : rgb(0 0 0) } .c{stroke-width:2;color:red}</style>
            <rect fill="#ff0000"/><line stroke="var(--ink)"/><path style="fill:hsl(0 0% 0%)"/><stop stop-color="blue"/>
            <rect fill="none" stroke="currentColor"/><rect fill="url(#grad)"/>
            </svg>
            """
        #expect(
            Set(NoteFigure.problems(svg)) == [
                .color("#222"), .color("rgb(0 0 0)"), .color("red"), .color("#ff0000"), .color("var(--ink)"), .color("hsl(0 0% 0%)"),
                .color("blue"),
            ])
    }

    @Test func longTextAndBigArrowheadsAreCaught() {
        let long = String(repeating: "가", count: FigureStyle.labelLimit + 1)
        let fits = String(repeating: "가", count: FigureStyle.labelLimit - 2) + " $\\frac{a}{b}$"
        let svg = """
            <svg xmlns="http://www.w3.org/2000/svg"><text>\(long)</text><text>\(fits)</text>
            <marker id="big" markerWidth="12" markerHeight="4"/><marker id="wide" markerUnits="userSpaceOnUse" markerWidth="9" markerHeight="9"/>
            <marker id="ok" markerUnits="userSpaceOnUse" markerWidth="9" markerHeight="6"/><marker/>
            </svg>
            """
        #expect(Set(NoteFigure.problems(svg)) == [.longText(long), .bigArrow("#big"), .bigArrow("#wide")])
    }

    // 쓸 때 넣은 스타일에는 hex 색이 있다. 이미 마무리한 그림을 다시 검사해도 걸리지 않아야 한다.
    @Test func theInsertedStyleIsNotChecked() {
        let svg = """
            <svg xmlns="http://www.w3.org/2000/svg"><style id="\(FigureStyle.styleID)">\(FigureStyle.css)</style>\
            <defs id="\(FigureStyle.defsID)">\(FigureStyle.marker(FigureStyle.ink))</defs><text class="ink">x</text></svg>
            """
        #expect(NoteFigure.problems(svg).isEmpty)
    }

    @Test func scriptsAndOutsideReferencesAreCaught() {
        let svg = """
            <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
            <style>@import url("https://fonts.example/a.css"); @font-face{src:url(font.woff)}</style>
            <script>alert(1)</script><rect onclick="x()" style="fill:url(http://x/p.svg#g)"/>
            <image xlink:href="photo.png"/><a href="https://example.com"><text>t</text></a>
            </svg>
            """
        let found = Set(NoteFigure.problems(svg))
        #expect(
            found == [
                .script("<script>"), .script("onclick"), .external("http://x/p.svg#g"), .external("photo.png"),
                .external("https://example.com"),
                .external("https://fonts.example/a.css"), .external("font.woff"), .external("url(\"https://fonts.example/a.css\")"),
            ])
    }

    @Test func brokenXMLAndOtherRootsAreCaught() {
        guard case .notXML(let line, _)? = NoteFigure.problems("<svg>\n<g>\n</svg>").first else {
            Issue.record("not caught")
            return
        }
        #expect(line >= 2)
        #expect(NoteFigure.problems(#"<html><p>x</p></html>"#) == [.notSVG(root: "html")])
    }

    @Test func widgetsLoadNothingFromOutside() {
        #expect(NoteWidget.problems(" \n") == [.empty])
        #expect(NoteWidget.problems(#"<div><a href="https://example.com">링크</a></div><script>let x = 1</script>"#).isEmpty)
        let page = """
            <script src="https://cdn.example/d3.js"></script><link rel="stylesheet" href="style.css">
            <img src="//cdn.example/a.png"><style>@import url(https://fonts.example/f.css); .a{background:url('https://x/b.png')}</style>
            """
        #expect(
            Set(NoteWidget.problems(page)) == [
                .external("https://cdn.example/d3.js"), .external("style.css"), .external("//cdn.example/a.png"),
                .external("https://fonts.example/f.css"), .external("https://x/b.png"),
            ])

        // frame은 위젯 자신의 파일만 받으므로, 그 옆의 파일도 다른 사이트의 파일처럼 바깥 참조다.
        let relative = """
            <script src="chart.js"></script><img src=plot.png><div style="background:url(grid.svg)"></div>
            <style>@import "theme.css";</style><script>const i = new Image(); i.src = 'dot.png'</script>
            """
        #expect(
            Set(NoteWidget.problems(relative)) == [
                .external("chart.js"), .external("plot.png"), .external("grid.svg"),
                .external("theme.css"), .external("dot.png"),
            ])

        let own = """
            <img src="data:image/png;base64,iVBO"><img src='blob:x'><use href="#a"/><div data-src="later.png"></div>
            <script>img.src = url; img.src = `${base}.png`; el.style.background = `url(${made})`</script>
            """
        #expect(NoteWidget.problems(own).isEmpty)
    }

    @Test func widgetFilesSitInTheCourseMetadata() {
        let id = UUID(uuidString: "FA090AB5-3039-4DDC-9011-498363A9A2D3")!
        #expect(NoteWidget.path(id) == ".folio/widgets/FA090AB5-3039-4DDC-9011-498363A9A2D3.html")
        let note = URL(filePath: "/g/2026-3/EC4207 그래프 이론/Notes/정리")
        #expect(
            StandardLayout.widgetFile(id, noteFolder: note)?.path
                == "/g/2026-3/EC4207 그래프 이론/.folio/widgets/FA090AB5-3039-4DDC-9011-498363A9A2D3.html")
    }

    @Test func thePolicyGoesAfterTheDoctypeOnItsLine() {
        let page = Data("<!DOCTYPE html>\n<p>x</p>".utf8)
        let text = String(decoding: NoteWidget.withPolicy(page), as: UTF8.self)
        #expect(text.hasPrefix("<!DOCTYPE html><meta http-equiv=\"Content-Security-Policy\""))
        #expect(text.split(separator: "\n").count == 2)
    }

    @Test func contentHashIsTheTextsSHA256() {
        #expect(ContentHash.of("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }
}
