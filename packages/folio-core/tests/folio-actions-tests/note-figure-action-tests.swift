import FolioActions
import FolioDomain
import FolioFixtures
import FolioStorage
import Foundation
import Testing

struct NoteFigureActionTests {
    static let course = ActionTests.graphTheory
    static let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><style>.a{fill:#222}@media (prefers-color-scheme: dark){.a{fill:#E6E2DB}}</style><rect class="a" width="10" height="10"/></svg>"#
    static let widget = UUID(uuidString: "A0000000-0000-4000-8000-0000000000A7")!
    let device = UUID()
    let gist: GISTStore
    let store: CourseStore

    init() throws {
        gist = GISTStore(url: try Fixture.standard.copyToTemp())
        store = try ActionContext(gist: gist, device: device).store(Self.course)
    }

    @discardableResult
    func run(_ action: some Action, dryRun: Bool = false) throws -> ActionContext {
        let ctx = ActionContext(gist: gist, device: device, now: Date(timeIntervalSince1970: 1_790_000_000), dryRun: dryRun)
        try action.run(ctx)
        return ctx
    }

    func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: store.fileURL(path).path) }

    @Test func addWritesTheFigureIntoAssets() throws {
        let ctx = try run(NoteFigureAdd(course: Self.course, name: "graph", svg: Self.svg))
        #expect(try store.readText("Notes/assets/graph.svg") == Self.svg)
        #expect(ctx.changes.map(\.kind) == [.added])
        #expect(ctx.changes.allSatisfy { $0.touchesNotes })
    }

    /// Another note may show the picture already there.
    @Test func aTakenNameIsLeftAsItIs() throws {
        try store.writeText("Notes/assets/graph.svg", text: "원래")
        #expect(throws: ActionError.self) { try run(NoteFigureAdd(course: Self.course, name: "graph.svg", svg: Self.svg)) }
        #expect(try store.readText("Notes/assets/graph.svg") == "원래")
    }

    @Test func aFigureThatWouldDrawWrongIsNotWritten() throws {
        let light = #"<svg xmlns="http://www.w3.org/2000/svg"><rect/></svg>"#
        #expect(throws: ActionError.rule(NoteFigure.Problem.noDarkRule.message)) {
            try run(NoteFigureAdd(course: Self.course, name: "g", svg: light))
        }
        #expect(throws: ActionError.self) { try run(NoteFigureAdd(course: Self.course, name: "../g", svg: Self.svg)) }
        #expect(!exists("Notes/assets/g.svg"))
    }

    @Test func writeReplacesOnlyWhatWasRead() throws {
        try run(NoteFigureAdd(course: Self.course, name: "graph", svg: Self.svg))
        let changed = Self.svg.replacing("width=\"10\"", with: "width=\"8\"")
        #expect(throws: ActionError.conflict("Notes/assets/graph.svg이(가) 읽은 뒤에 바뀌었습니다. 다시 읽고 고칩니다")) {
            try run(NoteFigureWrite(course: Self.course, name: "graph", svg: changed, expect: ContentHash.of("다른 내용")))
        }
        #expect(try store.readText("Notes/assets/graph.svg") == Self.svg)
        try run(NoteFigureWrite(course: Self.course, name: "graph.svg", svg: changed, expect: ContentHash.of(Self.svg).uppercased()))
        #expect(try store.readText("Notes/assets/graph.svg") == changed)
        #expect(throws: ActionError.self) {
            try run(NoteFigureWrite(course: Self.course, name: "none", svg: changed, expect: ContentHash.of(changed)))
        }
    }

    @Test func aDryRunWritesNothing() throws {
        let ctx = try run(NoteFigureAdd(course: Self.course, name: "graph", svg: Self.svg), dryRun: true)
        #expect(ctx.changes.contains { $0.kind == .added && $0.path.hasSuffix("Notes/assets/graph.svg") })
        #expect(!exists("Notes/assets/graph.svg"))
        try run(NoteWidgetAdd(course: Self.course, id: Self.widget, html: "<p>x</p>"), dryRun: true)
        #expect(!exists(NoteWidget.path(Self.widget)))
    }

    @Test func widgetAddMakesItsFileAndReportsTheID() throws {
        let ctx = try run(NoteWidgetAdd(course: Self.course, id: Self.widget, html: "<p>x</p>"))
        #expect(ctx.made == Self.widget)
        #expect(try store.readText(NoteWidget.path(Self.widget)) == "<p>x</p>")

        // An open note draws its widgets again only when its notes change.
        #expect(ctx.changes.allSatisfy { $0.touchesNotes })
        #expect(throws: ActionError.self) { try run(NoteWidgetAdd(course: Self.course, id: Self.widget, html: "<p>y</p>")) }
        #expect(throws: ActionError.self) {
            try run(NoteWidgetAdd(course: Self.course, id: UUID(), html: #"<script src="https://cdn.example/d3.js"></script>"#))
        }
    }

    @Test func widgetWriteChecksTheHash() throws {
        try run(NoteWidgetAdd(course: Self.course, id: Self.widget, html: "<p>x</p>"))
        #expect(throws: ActionError.self) {
            try run(NoteWidgetWrite(course: Self.course, widget: Self.widget, html: "<p>y</p>", expect: ContentHash.of("<p>z</p>")))
        }
        try run(NoteWidgetWrite(course: Self.course, widget: Self.widget, html: "<p>y</p>", expect: ContentHash.of("<p>x</p>")))
        #expect(try store.readText(NoteWidget.path(Self.widget)) == "<p>y</p>")
    }
}
