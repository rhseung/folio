import FolioDomain
import Foundation
import Testing

struct NoteFigureTests {
    static let good = """
    <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 100 40">
    <style>.ink{fill:#222}@media (prefers-color-scheme: dark){.ink{fill:#E6E2DB}}</style>
    <defs><marker id="arrow"><path d="M0 0L4 2L0 4z"/></marker></defs>
    <path d="M0 0L10 10" marker-end="url(#arrow)"/><use xlink:href="#arrow"/>
    <image href="data:image/png;base64,iVBORw0KGgo="/><text class="ink" x="4" y="20">매칭</text>
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

    @Test func aSelfContainedFigureWithADarkRulePasses() {
        #expect(NoteFigure.problems(Self.good).isEmpty)
    }

    @Test func aFigureWithoutADarkRuleIsCaught() {
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg"><style>.a{fill:#222}</style><text class="a">x</text></svg>"#
        #expect(NoteFigure.problems(svg) == [.noDarkRule])
        // A light-only query is not a dark rule.
        let light = #"<svg xmlns="http://www.w3.org/2000/svg"><style>@media (prefers-color-scheme: light){.a{fill:#222}}</style></svg>"#
        #expect(NoteFigure.problems(light) == [.noDarkRule])
    }

    @Test func scriptsAndOutsideReferencesAreCaught() {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
        <style>@import url("https://fonts.example/a.css"); @font-face{src:url(font.woff)}
        @media (prefers-color-scheme: dark){.a{fill:#fff}}</style>
        <script>alert(1)</script><rect onclick="x()" style="fill:url(http://x/p.svg#g)"/>
        <image xlink:href="photo.png"/><a href="https://example.com"><text>t</text></a>
        </svg>
        """
        let found = Set(NoteFigure.problems(svg))
        #expect(found == [
            .script("<script>"), .script("onclick"), .external("http://x/p.svg#g"), .external("photo.png"), .external("https://example.com"),
            .external("https://fonts.example/a.css"), .external("font.woff"), .external("url(\"https://fonts.example/a.css\")"),
        ])
    }

    @Test func brokenXMLAndOtherRootsAreCaught() {
        guard case .notXML(let line, _)? = NoteFigure.problems("<svg>\n<g>\n</svg>").first else {
            Issue.record("not caught")
            return
        }
        #expect(line >= 2)
        #expect(NoteFigure.problems(#"<html><style>@media (prefers-color-scheme: dark){}</style></html>"#) == [.notSVG(root: "html")])
    }

    @Test func forcedPicksOneAppearance() {
        let svg = "@media (prefers-color-scheme: dark){a} @media (prefers-color-scheme:light){b}"
        #expect(NoteFigure.forced(svg, dark: true) == "@media (min-width:0px){a} @media (max-width:0px){b}")
        #expect(NoteFigure.forced(svg, dark: false) == "@media (max-width:0px){a} @media (min-width:0px){b}")
    }

    @Test func widgetsLoadNothingFromOutside() {
        #expect(NoteWidget.problems(" \n") == [.empty])
        #expect(NoteWidget.problems(#"<div><a href="https://example.com">링크</a></div><script>let x = 1</script>"#).isEmpty)
        let page = """
        <script src="https://cdn.example/d3.js"></script><link rel="stylesheet" href="style.css">
        <img src="//cdn.example/a.png"><style>@import url(https://fonts.example/f.css); .a{background:url('https://x/b.png')}</style>
        """
        #expect(Set(NoteWidget.problems(page)) == [
            .external("https://cdn.example/d3.js"), .external("style.css"), .external("//cdn.example/a.png"),
            .external("https://fonts.example/f.css"), .external("https://x/b.png"),
        ])
        // The frame is served only the widget's own file, so a file beside it is as far away as another site.
        let relative = """
        <script src="chart.js"></script><img src=plot.png><div style="background:url(grid.svg)"></div>
        <style>@import "theme.css";</style><script>const i = new Image(); i.src = 'dot.png'</script>
        """
        #expect(Set(NoteWidget.problems(relative)) == [.external("chart.js"), .external("plot.png"), .external("grid.svg"),
                                                       .external("theme.css"), .external("dot.png")])
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
        #expect(StandardLayout.widgetFile(id, noteFolder: note)?.path == "/g/2026-3/EC4207 그래프 이론/.folio/widgets/FA090AB5-3039-4DDC-9011-498363A9A2D3.html")
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
