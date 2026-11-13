import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Testing

@testable import FolioCLI

struct NoteFigureCommandTests {
    let h = Harness()
    let course = Harness.graphTheory
    static let svg =
        #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 40"><style>.a{fill:#222}@media (prefers-color-scheme: dark){.a{fill:#E6E2DB}}</style><rect class="a" width="60" height="40"/></svg>"#
    static let widget = UUID(uuidString: "A0000000-0000-4000-8000-0000000000A7")!

    func scratch(_ name: String, _ text: String) throws -> String {
        let url = FileManager.default.temporaryDirectory.appending(path: "folio-cli-\(UUID().uuidString)").appending(path: name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    func addFigure() throws -> [String] { ["note", "figure", "add", "EC4207", "graph", "--svg", try scratch("graph.svg", Self.svg)] }
    func addWidget() throws -> [String] {
        ["note", "widget", "add", "EC4207", "--html", try scratch("w.html", "<p>x</p>"), "--id", Self.widget.uuidString]
    }

    @Test func figureAdd() throws {
        try h.expectSame(try addFigure()) { _ in NoteFigureAdd(course: course, name: "graph", svg: Self.svg) }
    }

    @Test func figureWrite() throws {
        let new = Self.svg.replacing("60", with: "80")
        try h.expectSame(
            ["note", "figure", "write", "EC4207", "graph.svg", "--svg", try scratch("new.svg", new), "--expect", ContentHash.of(Self.svg)],
            setup: [try addFigure()]
        ) { _ in
            NoteFigureWrite(course: course, name: "graph.svg", svg: new, expect: ContentHash.of(Self.svg))
        }
    }

    @Test func widgetAdd() throws {
        try h.expectSame(try addWidget()) { _ in NoteWidgetAdd(course: course, id: Self.widget, html: "<p>x</p>") }
    }

    @Test func widgetWrite() throws {
        try h.expectSame(
            [
                "note", "widget", "write", "EC4207/\(Self.widget.uuidString)", "--html", try scratch("y.html", "<p>y</p>"),
                "--expect", ContentHash.of("<p>x</p>"),
            ], setup: [try addWidget()]
        ) { _ in
            NoteWidgetWrite(course: course, widget: Self.widget, html: "<p>y</p>", expect: ContentHash.of("<p>x</p>"))
        }
    }

    @Test func showAndListRead() throws {
        let gist = try Harness.fixtureCopy()
        #expect(h.cli(try addFigure(), gist: gist).code == 0)
        #expect(h.cli(try addWidget(), gist: gist).code == 0)
        let shown = h.cli(["note", "figure", "show", "EC4207", "graph", "--json"], gist: gist)
        let body = try JSONDecoder().decode(JSONValue.self, from: Data(shown.out.utf8))
        #expect(body["hash"] == .string(ContentHash.of(Self.svg)))
        #expect(body["path"] == .string("Notes/assets/graph.svg"))
        let widget = h.cli(["note", "widget", "show", "EC4207/\(Self.widget.uuidString)", "--json"], gist: gist)
        #expect(try JSONDecoder().decode(JSONValue.self, from: Data(widget.out.utf8))["hash"] == .string(ContentHash.of("<p>x</p>")))
        #expect(h.cli(["note", "widget", "show", "EC4207/not-an-id"], gist: gist).code == Exit.usage.rawValue)
        #expect(h.cli(["note", "figure", "show", "EC4207", "none"], gist: gist).code == Exit.notFound.rawValue)
        #expect(h.cli(["note", "figure", "list", "EC4207"], gist: gist).out.contains("graph.svg"))
        #expect(h.cli(["note", "widget", "list", "EC4207"], gist: gist).out.contains(Self.widget.uuidString))
    }

    @Test func formatPrintsTheGuide() throws {
        let r = h.cli(["note", "format"], gist: try Harness.fixtureCopy())
        #expect(r.out.contains("prefers-color-scheme: dark"))
        #expect(r.out.contains("cb-widget"))
        #expect(Skill.text.contains("### 그림(SVG)"))
    }

    @Test func thePanelProposesFiguresAndWidgets() throws {
        let gist = try Harness.fixtureCopy()
        let before = try Harness.files(gist)
        for (tool, arguments) in [
            ("note_figure_add", ["course": "EC4207", "name": "graph", "svg": .string(Self.svg)] as JSONValue),
            ("note_widget_add", ["course": "EC4207", "html": "<p>x</p>"]),
        ] {
            let (failed, texts) = try MCPTests().call(MCPServer(gist: nil, propose: true), gist, tool, arguments)
            #expect(!failed, "\(texts)")
            let proposal = try #require(texts.compactMap(ActionProposal.init(text:)).first)
            #expect(proposal.input["course"] == .string(course.uuidString))
        }
        #expect(try Harness.files(gist) == before)
    }

    // base64를 글로 읽으면 수만 토큰이 들기 때문에 그림을 글에서 떼어 낸다.
    @Test func renderedPicturesBecomeImageContent() throws {
        var text = #"{"console":["error: x"],"images":[{"height":40,"png":"iVBO","theme":"light","width":480}],"problems":[]}"#
        let images = MCPServer.images(&text)
        #expect(images == [["type": "image", "data": "iVBO", "mimeType": "image/png"]])
        #expect(!text.contains("iVBO"))
        #expect(text.contains("\"theme\":\"light\""))
        var plain = #"{"path":"a.png"}"#
        #expect(MCPServer.images(&plain).isEmpty)
        #expect(plain == #"{"path":"a.png"}"#)
    }

    // WebKit은 main queue에서 응답하는데, main actor에서 도는 Swift Testing 테스트는 이미 그 queue 안에 있다. 그래서 렌더는 별도 프로세스에서만 검사할 수 있으므로, 이
    // 테스트 번들 옆에 빌드된 `folio`를 쓴다.
    static let folio: URL? = {
        // `swift test`는 번들 경로를 runner에 넘기고, Xcode는 번들로 불러온다.
        let bundles = CommandLine.arguments.map { URL(filePath: $0) } + Bundle.allBundles.map(\.bundleURL)
        return bundles.lazy.compactMap { url -> URL? in
            guard let i = url.pathComponents.lastIndex(where: { $0.hasSuffix(".xctest") }) else { return nil }
            let folder = url.pathComponents[..<i].reduce(URL(filePath: "/")) { $0.appending(path: $1) }
            return folder.appending(path: "folio")
        }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }()

    func render(_ args: [String]) throws -> RenderResult {
        let p = Process()
        p.executableURL = try #require(Self.folio)
        p.arguments = args + ["--width", "300", "--json", "--gist", try Harness.fixtureCopy().path]
        let out = Pipe()
        p.standardOutput = out
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        #expect(p.terminationStatus == 0)
        return try JSONDecoder().decode(RenderResult.self, from: data)
    }

    @Test(.enabled(if: folio != nil)) func rendersAFigureInBothAppearances() throws {
        let result = try render(["note", "figure", "render", "--text", Self.svg])
        #expect(result.images.map(\.theme) == ["light", "dark"])
        #expect(result.problems.isEmpty)
        let pngs = result.images.compactMap { Data(base64Encoded: $0.png) }
        #expect(pngs.count == 2)
        #expect(pngs.allSatisfy { $0.starts(with: [0x89, 0x50, 0x4E, 0x47]) })
        #expect(pngs[0] != pngs[1])
        #expect(result.images.allSatisfy { $0.width == 300 && $0.height > 40 })
    }

    @Test(.enabled(if: folio != nil)) func rendersAWidgetAndCollectsItsErrors() throws {
        let result = try render(["note", "widget", "render", "--text", "<!doctype html>\n<p>x</p>\n<script>\nundefinedFn()\n</script>"])
        #expect(result.images.count == 2)
        #expect(result.console.contains { $0.contains("undefinedFn") && $0.contains("line 4") }, "\(result.console)")
    }
}
