import FolioActions
import FolioDomain
import FolioMarkdown
import Foundation
import Testing

@testable import Folio

@MainActor
struct AssetTrayModelTests {
    static let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><rect class="ink" width="10" height="10"/></svg>"#
    static let widget = UUID(uuidString: "A0000000-0000-4000-8000-0000000000B1") ?? UUID()
    let workspace: Workspace
    let editor: NoteEditorModel
    let tray: AssetTrayModel

    init() throws {
        workspace = try fixtureWorkspace()
        let id = try #require(workspace.run(NoteAdd(course: graphTheory, title: "서랍", kind: .free))?.made)
        workspace.run(NoteFigureAdd(course: graphTheory, name: "hall", svg: Self.svg))
        workspace.run(NoteFigureAdd(course: graphTheory, name: "konig", svg: Self.svg))
        workspace.run(NoteWidgetAdd(course: graphTheory, id: Self.widget, html: "<title>증가 경로</title><p>x</p>"))
        let course = try #require(workspace.course(graphTheory))
        let note = try #require(try course.store.note(id: id))
        editor = NoteEditorModel(workspace: workspace, course: course, note: note)
        editor.load()
        tray = AssetTrayModel(editor: editor)
        tray.reload()
    }

    func names(_ assets: [NoteAsset]) -> Set<String> { Set(assets.map(tray.name)) }

    @Test func readsFiguresWidgetsAndTheirTitles() {
        #expect(names(tray.assets).isSuperset(of: ["hall.svg", "konig.svg", "증가 경로"]))
        #expect(tray.assets.first { $0.ref == .widget(Self.widget) }?.kind == .widget)
        #expect(tray.shelf.used.isEmpty)
    }

    @Test func insertingAFigurePutsItsLinkAndMovesItToUsed() throws {
        let hall = try #require(tray.assets.first { $0.name == "hall.svg" })
        tray.insert(hall)
        let link = try #require(editor.pendingInsert)
        #expect(link.hasSuffix("assets/hall.svg)"))
        editor.body += link
        #expect(names(tray.shelf.used) == ["hall.svg"])
        #expect(!names(tray.shelf.unused).contains("hall.svg"))
        #expect(tray.detail(hall) == "그림 · 이 노트에 있음")
    }

    @Test func insertingAWidgetPutsABlockAndCollapsesTheSheet() throws {
        let widget = try #require(tray.assets.first { $0.ref == .widget(Self.widget) })
        tray.expanded = true
        tray.insert(widget, collapsing: true)
        #expect(editor.pendingBlock == CBWidget.block(Self.widget))
        #expect(!tray.expanded)
        editor.body = "앞\n" + CBWidget.block(Self.widget) + "\n"
        #expect(tray.used(widget))
        #expect(tray.dragText(widget).hasPrefix("\n```cb-widget"))
    }

    @Test func filterAndSearchNarrowOnlyTheExpandedShelf() {
        tray.filter = .figures
        tray.search = "kon"
        #expect(names(tray.shelf.unused).isSuperset(of: ["hall.svg", "konig.svg", "증가 경로"]))
        tray.expanded = true
        #expect(names(tray.shelf.unused) == ["konig.svg"])
        tray.filter = .widgets
        tray.search = ""
        #expect(names(tray.shelf.unused) == ["증가 경로"])
    }

    @Test func viewingLargeChoosesByKind() throws {
        let hall = try #require(tray.assets.first { $0.name == "hall.svg" })
        tray.viewLarge(hall)
        #expect(tray.viewing == hall && tray.quickLook == nil)
        #expect(tray.figureText(hall)?.hasPrefix("![hall](") == true)
        #expect(tray.thumbnail(hall, dark: true, accent: .gray)?.dark == true)
    }
}
