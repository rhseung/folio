import FolioDomain
import FolioMarkdown
import Testing

@testable import Folio

@MainActor
struct InputGuideModelTests {
    @Test func tabsNarrowAndSearchLooksInTheTab() throws {
        let model = InputGuideModel(workspace: try fixtureWorkspace(), syntax: .latex)
        #expect(model.tabs.map { $0.0 } == [nil] + InputGuide.Section.allCases.map { Optional($0) })
        #expect(model.shown.map(\.section) == InputGuide.Section.allCases)
        model.section = .table
        #expect(model.shown.map(\.section) == [.table])
        model.search = TableCommands.title(.rowBelow)
        #expect(model.shown.first?.entries.map(\.title) == [.table(.rowBelow)])
        model.section = nil
        model.search = "python"
        #expect(model.shown.map(\.section) == [.menu])
        model.search = "없는 말"
        #expect(model.shown.isEmpty)
    }

    @Test func snippetsFollowTheNotesSyntax() throws {
        let workspace = try fixtureWorkspace()
        let tex = InputGuideModel(workspace: workspace, syntax: .latex)
        let ascii = InputGuideModel(workspace: workspace, syntax: .asciimath)
        let texTitles = tex.shown.flatMap(\.entries).map(\.title)
        let asciiTitles = ascii.shown.flatMap(\.entries).map(\.title)
        #expect(texTitles.contains(.code("\\frac{…}{…}")) && !texTitles.contains(.code("frac(…)(…)")))
        #expect(asciiTitles.contains(.code("frac(…)(…)")) && !asciiTitles.contains(.code("\\frac{…}{…}")))
        #expect(texTitles.contains(.named(String(localized: .notesAssistInlineMath))))
        #expect(InputGuideModel.words(.phrase(.blocks)) == String(localized: .notesGuideBlocks))
    }
}
