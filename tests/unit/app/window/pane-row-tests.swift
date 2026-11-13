import AppKit
import FolioDomain
import SwiftUI
import Testing

@testable import Folio

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
        NSApp.postEvent(up, atStart: false)
        NSApp.sendEvent(down)
    }

    @Test func foldsThePanePressedLongestAgoAndOpensAPressedStrip() async throws {
        let panes = try #require(tabs.front)
        panes.openBeside(Navigator.Entry(link: .place(.people)))
        panes.openBeside(Navigator.Entry(link: .place(.codes)))
        try await settle()
        // 1200은 360 이상인 칸 세 개를 담는다.
        #expect(widths.count == 3 && widths.allSatisfy { $0 >= Theme.Size.paneMin })

        // 900은 띠 옆에 칸 두 개를 담는다. 가장 오래전에 누른 성적이 접히고, 초점이 있는 코드는 접히지 않는다.
        window.setContentSize(NSSize(width: 900, height: 800))
        try await settle()
        #expect(widths[0] == Theme.Size.paneStrip && widths[1] >= Theme.Size.paneMin && widths[2] >= Theme.Size.paneMin)

        try click(probes[1])
        try await settle()
        #expect(panes.focus == 1)
        #expect(widths[0] == Theme.Size.paneStrip)

        panes.press(0)
        try await settle(1)
        #expect(widths[2] == Theme.Size.paneStrip && widths[0] >= Theme.Size.paneMin)
    }

    @Test func aDragMovesThePanelsAndTellsTheTabOnDrop() async throws {
        let panes = try #require(tabs.front)
        panes.openBeside(Navigator.Entry(link: .place(.people)))
        try await settle()
        let start = widths
        // 창이 화면 밖에 있고 key가 되지 않아 press를 받지 못하므로, 구분선의 gesture가 부르는 함수를 끈 거리로 직접 부른다.
        let drag = try #require(PaneDragHook.shared.row)
        drag.dragged(0, by: 100, folded: [])
        try await settle(0.05)
        #expect(abs(widths[0] - (start[0] + 100)) <= 1 && abs(widths[1] - (start[1] - 100)) <= 1)
        #expect(panes.shares == [0.5, 0.5])
        drag.dropped()
        try await settle()
        #expect(abs(panes.shares[0] - (start[0] + 100) / (start[0] + start[1])) < 1e-6)
        #expect(abs(widths[0] - (start[0] + 100)) <= 1)
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
        #expect(widths.allSatisfy { abs($0 - widths[0]) <= 1 })
    }

    @Test func aPaneFoldedByHandStaysAStripAsTheWindowWidens() async throws {
        let panes = try #require(tabs.front)
        panes.openBeside(Navigator.Entry(link: .place(.people)))
        try await settle()
        panes.collapse(1)
        try await settle(1)
        #expect(widths[1] == Theme.Size.paneStrip && abs(widths[0] - (1200 - Theme.Size.paneStrip - PaneRow.gap)) <= 1)
        window.setContentSize(NSSize(width: 1600, height: 800))
        try await settle()
        #expect(widths[1] == Theme.Size.paneStrip)
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
