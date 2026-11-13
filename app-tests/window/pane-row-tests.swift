import AppKit
import FolioDomain
import SwiftUI
import Testing

@testable import Folio

/// A tab's panes in a window (#62): where the row runs out the pane pressed longest ago folds into a strip, a click
/// anywhere in a pane focuses it, and pressing a strip opens it as another folds.
@MainActor @Suite(.serialized)
struct PaneRowTests {
    let workspace: Workspace
    let tabs: WindowTabs
    let window: NSWindow
    let host: NSView

    init() throws {
        workspace = try fixtureWorkspace()
        tabs = WindowTabs(Navigator(Navigator.Entry(link: .place(.grades))))
        let screens = TabScreens(tabs: tabs, workspace: workspace) { navigator in
            OpenLinkAction { link, _, course in navigator.go(Navigator.Entry(link: link, course: course)) }
        }
        .environment(workspace)
        host = NSHostingView(rootView: screens)
        window = NSWindow(
            contentRect: CGRect(x: -20_000, y: -20_000, width: 1200, height: 800), styleMask: [.borderless], backing: .buffered,
            defer: false)
        window.contentView = host
    }

    func settle(_ seconds: Double = 0.5) async throws {
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .seconds(seconds))
        host.layoutSubtreeIfNeeded()
    }

    /// The panes left to right, by the press probe each lies over (the dividers' take double clicks).
    var probes: [PanePress.Probe] {
        func find(_ view: NSView) -> [PanePress.Probe] {
            ((view as? PanePress.Probe).flatMap { $0.clicks == 1 ? [$0] : nil } ?? []) + view.subviews.flatMap(find)
        }
        return find(host).sorted { $0.convert(NSPoint.zero, to: nil).x < $1.convert(NSPoint.zero, to: nil).x }
    }

    var widths: [CGFloat] { probes.map(\.bounds.width) }

    func click(_ probe: NSView) throws {
        let point = probe.convert(NSPoint(x: probe.bounds.midX, y: probe.bounds.midY), to: nil)
        let down = try #require(
            NSEvent.mouseEvent(
                with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let up = try #require(
            NSEvent.mouseEvent(
                with: .leftMouseUp, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0))
        // Queued first, so whatever the press starts to track ends.
        NSApp.postEvent(up, atStart: false)
        NSApp.sendEvent(down)
    }

    @Test func foldsThePanePressedLongestAgoAndOpensAPressedStrip() async throws {
        let panes = try #require(tabs.front)
        panes.openBeside(Navigator.Entry(link: .place(.people)))
        panes.openBeside(Navigator.Entry(link: .place(.codes)))
        try await settle()
        // 1200 holds three panes at 360 and more.
        #expect(widths.count == 3 && widths.allSatisfy { $0 >= Theme.Size.paneMin })

        // 900 holds two beside a strip: grades, pressed longest ago, folds; the focused codes never does.
        window.setContentSize(NSSize(width: 900, height: 800))
        try await settle()
        #expect(widths[0] == Theme.Size.paneStrip && widths[1] >= Theme.Size.paneMin && widths[2] >= Theme.Size.paneMin)

        // A click anywhere in people focuses it; nothing folds anew.
        try click(probes[1])
        try await settle()
        #expect(panes.focus == 1)
        #expect(widths[0] == Theme.Size.paneStrip)

        // Pressing the strip opens grades and folds codes, now pressed longest ago.
        panes.press(0)
        try await settle(1)
        #expect(widths[2] == Theme.Size.paneStrip && widths[0] >= Theme.Size.paneMin)
    }

    @Test func aDragMovesThePanelsAndTellsTheTabOnDrop() async throws {
        let panes = try #require(tabs.front)
        panes.openBeside(Navigator.Entry(link: .place(.people)))
        try await settle()
        let start = widths
        // What the divider's gesture calls, by how far it went: off screen and never key, the window can't take a press.
        let drag = try #require(PaneDragHook.shared.row)
        drag.dragged(0, by: 100, folded: [])
        try await settle(0.05)
        #expect(abs(widths[0] - (start[0] + 100)) <= 1 && abs(widths[1] - (start[1] - 100)) <= 1)
        // The tab hears nothing until the drop.
        #expect(panes.shares == [0.5, 0.5])
        drag.dropped()
        try await settle()
        #expect(abs(panes.shares[0] - (start[0] + 100) / (start[0] + start[1])) < 1e-6)
        #expect(abs(widths[0] - (start[0] + 100)) <= 1)
        // A second drop, as when the gesture ends and its state resets, changes nothing.
        drag.dropped()
        #expect(abs(panes.shares[0] - (start[0] + 100) / (start[0] + start[1])) < 1e-6)
    }

    @Test func aDoubleClickOnADividerEvensThePanes() async throws {
        let panes = try #require(tabs.front)
        panes.openBeside(Navigator.Entry(link: .place(.people)))
        panes.openBeside(Navigator.Entry(link: .place(.codes)))
        panes.resize(divider: 0, to: 0.3)
        try await settle()
        let left = probes[0].convert(NSPoint(x: probes[0].bounds.maxX, y: probes[0].bounds.midY), to: nil)
        // Past the gap, in the margin either side that catches the pointer too.
        let at = NSPoint(x: left.x + PaneRow.gap + 2, y: left.y)
        for clicks in 1...2 {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try #require(
                    NSEvent.mouseEvent(
                        with: type, location: at, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                        context: nil, eventNumber: 0, clickCount: clicks, pressure: type == .leftMouseUp ? 0 : 1))
                if type == .leftMouseUp { NSApp.postEvent(event, atStart: false) } else { NSApp.sendEvent(event) }
            }
        }
        try await settle(1)
        #expect(panes.shares.allSatisfy { abs($0 - 1.0 / 3) < 1e-9 })
        let widths = widths
        // Each rounded to the screen's pixels.
        #expect(widths.allSatisfy { abs($0 - widths[0]) <= 1 })
    }

    @Test func aPaneFoldedByHandStaysAStripAsTheWindowWidens() async throws {
        let panes = try #require(tabs.front)
        panes.openBeside(Navigator.Entry(link: .place(.people)))
        try await settle()
        panes.collapse(1)
        try await settle(1)
        // The other pane takes what the strip leaves.
        #expect(widths[1] == Theme.Size.paneStrip && abs(widths[0] - (1200 - Theme.Size.paneStrip - PaneRow.gap)) <= 1)
        window.setContentSize(NSSize(width: 1600, height: 800))
        try await settle()
        #expect(widths[1] == Theme.Size.paneStrip)
        // Pressing the strip opens it at its share again.
        panes.press(1)
        try await settle(1)
        #expect(widths.allSatisfy { abs($0 - widths[0]) <= 1 })
    }

    @Test func aLonePaneTakesTheWholeRow() async throws {
        try await settle()
        #expect(widths == [1200])
        window.setContentSize(NSSize(width: 300, height: 800))
        try await settle()
        #expect(widths == [300])
    }
}
