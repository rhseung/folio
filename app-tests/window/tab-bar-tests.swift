#if os(macOS)
import AppKit
import FolioDomain
import SwiftUI
import Testing
@testable import Folio

/// Closing a pane of the tab in front (#62) with the tab bar and the panes drawn. A segment of the tab going away was
/// drawn once more with the place it had, reading past the end of the panes, and the app crashed (2026-11-08).
@MainActor @Suite(.serialized)
struct TabBarTests {
    let workspace: Workspace
    let tabs: WindowTabs
    let window: NSWindow
    let host: NSView

    init() throws {
        let workspace = try fixtureWorkspace()
        let tabs = WindowTabs(Navigator(Navigator.Entry(link: .place(.grades))))
        tabs.open(Navigator(Navigator.Entry(link: .place(.codes))))
        self.workspace = workspace
        self.tabs = tabs
        let row = ToolbarRow()
        row.windowWidth = 1400
        let view = VStack(spacing: 0) {
            TabBar(tabs: tabs, workspace: workspace, crumbs: [], toolbar: row, moveToWindow: { _ in })
            TabScreens(tabs: tabs, workspace: workspace) { navigator in
                OpenLinkAction { link, _, course in navigator.go(Navigator.Entry(link: link, course: course)) }
            }
        }
        .environment(workspace)
        host = NSHostingView(rootView: view)
        window = NSWindow(
            contentRect: CGRect(x: -20_000, y: -20_000, width: 1400, height: 800), styleMask: [.borderless], backing: .buffered,
            defer: false)
        window.contentView = host
    }

    func settle() async throws {
        host.layoutSubtreeIfNeeded()
        host.display()
        try await Task.sleep(for: .seconds(0.6))
        host.layoutSubtreeIfNeeded()
        host.display()
    }

    func panes(_ entries: [Navigator.Entry]) async throws -> TabPanes {
        let panes = try #require(tabs.front)
        for entry in entries { panes.openBeside(entry) }
        try await settle()
        return panes
    }

    @Test func closingAPaneOfTwo() async throws {
        let panes = try await panes([Navigator.Entry(link: .place(.people))])
        let left = panes.ids[0]
        #expect(panes.close(pane: panes.ids[1]))
        try await settle()
        #expect(panes.ids == [left])
    }

    @Test func closingTheFocusedPaneOfTwo() async throws {
        let panes = try await panes([Navigator.Entry(link: .place(.people))])
        let right = panes.ids[1]
        panes.press(pane: right)
        panes.press(pane: panes.ids[0])
        #expect(panes.focus == 0)
        #expect(panes.close(pane: panes.ids[0]))
        try await settle()
        #expect(panes.ids == [right])
    }

    @Test func closingTheMiddleOfThree() async throws {
        let panes = try await panes([Navigator.Entry(link: .place(.people)), Navigator.Entry(link: .place(.settings))])
        let (first, last) = (panes.ids[0], panes.ids[2])
        #expect(panes.close(pane: panes.ids[1]))
        try await settle()
        #expect(panes.ids == [first, last])
        #expect(panes.close(pane: last))
        try await settle()
        #expect(panes.ids == [first])
    }

    @Test func closingAFoldedPane() async throws {
        let panes = try await panes([Navigator.Entry(link: .place(.people)), Navigator.Entry(link: .place(.settings))])
        panes.collapse(0)
        try await settle()
        #expect(panes.folded.contains(0))
        let rest = Array(panes.ids.dropFirst())
        #expect(panes.close(pane: panes.ids[0]))
        try await settle()
        #expect(panes.ids == rest && panes.folded.isEmpty)
        #expect(panes.close(pane: rest[1]))
        try await settle()
        #expect(panes.ids == [rest[0]])
    }

    @Test func aPaneAlreadyClosedIsLeftAlone() async throws {
        let panes = try await panes([Navigator.Entry(link: .place(.people)), Navigator.Entry(link: .place(.settings))])
        let gone = panes.ids[1]
        #expect(panes.close(pane: gone))
        let left = panes.ids
        let focus = panes.focus
        // A press or a close from what drew the closed pane changes nothing, not the pane now in its place.
        #expect(!panes.close(pane: gone))
        panes.press(pane: gone)
        #expect(panes.ids == left && panes.focus == focus)
    }
}
#endif
