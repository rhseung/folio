import FolioDomain
import Foundation
import Testing

@testable import Folio

// 탭 줄은 창의 (100, 8)에서 시작하고, 탭은 줄 안에서 130pt마다 120pt 폭으로 선다. 본문은 줄 아래 (200, 48)부터다.
@MainActor
struct TabDragTests {
    let grades = Navigator.Entry(link: .place(.grades))
    let people = Navigator.Entry(link: .place(.people))
    let codes = Navigator.Entry(link: .place(.codes))
    let settings = Navigator.Entry(link: .place(.settings))

    func window(_ entries: [Navigator.Entry]) -> WindowTabs {
        let tabs = WindowTabs(Navigator(entries[0]))
        for entry in entries.dropFirst() { tabs.open(Navigator(entry)) }
        tabs.select(tabs.ids[0])
        lay(tabs)
        return tabs
    }

    func lay(_ tabs: WindowTabs) {
        let drag = tabs.dragging
        drag.strip = CGRect(x: 100, y: 8, width: 800, height: 32)
        drag.row = tabs.ids
        drag.frames = Dictionary(
            uniqueKeysWithValues: tabs.ids.enumerated().map { ($1, CGRect(x: CGFloat($0) * 130, y: 0, width: 120, height: 32)) })
        tabs.contentFrame = CGRect(x: 200, y: 48, width: 1000, height: 700)
    }

    // 줄 공간의 자리에서 창의 global 자리로 옮긴다.
    func global(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: 100 + x, y: 8 + y) }

    func pull(_ tabs: WindowTabs, _ item: TabDrop.Item, from: CGPoint, to: CGPoint) {
        tabs.dragging.changed(item, location: from, start: from, translation: 0)
        tabs.dragging.changed(item, location: to, start: from, translation: to.x - from.x)
    }

    func drop(_ tabs: WindowTabs, _ item: TabDrop.Item, from: CGPoint, to: CGPoint) {
        pull(tabs, item, from: from, to: to)
        tabs.dragging.ended(item, location: to)
    }

    @Test func aTabMovesAlongItsStripWhileDragged() {
        let tabs = window([grades, people, codes])
        tabs.dragging.find = { [weak tabs] in (tabs?.dragging, $0) }
        let (a, b, c) = (tabs.ids[0], tabs.ids[1], tabs.ids[2])
        pull(tabs, .tab(a), from: CGPoint(x: 60, y: 16), to: CGPoint(x: 330, y: 16))
        #expect(tabs.ids == [b, c, a])
        #expect(tabs.dragging.dragged == .tab(a) && !tabs.dragging.lifted && tabs.dragging.caret == nil)
        tabs.dragging.ended(.tab(a), location: CGPoint(x: 330, y: 16))
        #expect(tabs.ids == [b, c, a] && tabs.count == 3)
        #expect(tabs.dragging.dragged == nil && tabs.dragging.offset == 0)
    }

    @Test func aTabDroppedOnAnotherWindowsStripJoinsItThere() throws {
        let here = window([grades, people])
        let there = window([codes, settings])
        here.dragging.find = { [weak there] in (there?.dragging, $0) }
        let moving = here.ids[1]
        let panes = try #require(here.panes(moving))
        let (first, second) = (there.ids[0], there.ids[1])

        pull(here, .tab(moving), from: CGPoint(x: 190, y: 16), to: CGPoint(x: 140, y: 16))
        #expect(there.dragging.caret == 126 && here.dragging.caret == nil && here.dragging.lifted)
        here.dragging.ended(.tab(moving), location: CGPoint(x: 140, y: 16))

        #expect(here.ids.count == 1 && here.panes(moving) == nil)
        #expect(there.count == 3 && there.ids[0] == first && there.ids[2] == second)
        #expect(there.selected == there.ids[1] && there.front === panes)
        #expect(there.dragging.caret == nil)
    }

    @Test func theLastTabTakesItsWindowAlong() {
        let here = window([grades])
        let there = window([codes])
        var closed = false
        here.closeWindow = { closed = true }
        here.dragging.find = { [weak there] in (there?.dragging, $0) }
        drop(here, .tab(here.ids[0]), from: CGPoint(x: 60, y: 16), to: CGPoint(x: 200, y: 16))
        #expect(closed && there.count == 2 && there.current.current == grades)
    }

    @Test func aTabDroppedOnAnotherWindowsEdgeJoinsItsFrontTab() {
        let here = window([grades, people])
        let there = window([codes])
        here.dragging.find = { [weak there] in (there?.dragging, $0) }
        let moving = here.ids[1]
        pull(here, .tab(moving), from: CGPoint(x: 190, y: 16), to: CGPoint(x: 110, y: 400))
        #expect(there.drop == WindowTabs.MergeDrop(edge: .leading, share: 0.5) && here.drop == nil)
        here.dragging.ended(.tab(moving), location: CGPoint(x: 110, y: 400))
        #expect(here.count == 1 && there.count == 1 && there.drop == nil)
        #expect(there.front?.navigators.map(\.current) == [people, codes])
    }

    @Test func aTabDroppedAwayFromEveryWindowOpensOneWithItsHistory() throws {
        let tabs = window([grades, people])
        tabs.dragging.find = { (nil, $0) }
        var opened: [WindowRequest] = []
        tabs.dragging.openWindow = { opened.append($0) }
        let moving = tabs.ids[1]
        tabs.panes(moving)?.focused.go(settings)
        drop(tabs, .tab(moving), from: CGPoint(x: 190, y: 16), to: CGPoint(x: 400, y: 900))
        let request = try #require(opened.first)
        #expect(tabs.count == 1 && request.link == settings.link)
        #expect(request.history?.back.map(\.link) == [people.link])

        let alone = window([codes])
        alone.dragging.find = { (nil, $0) }
        alone.dragging.openWindow = { opened.append($0) }
        drop(alone, .tab(alone.ids[0]), from: CGPoint(x: 60, y: 16), to: CGPoint(x: 400, y: 900))
        #expect(opened.count == 1 && alone.count == 1)
    }

    @Test func theFrontTabTornIntoItsOwnPageOpensAWindow() {
        let tabs = window([grades, people])
        tabs.dragging.find = { [weak tabs] in (tabs?.dragging, $0) }
        var opened = 0
        tabs.dragging.openWindow = { _ in opened += 1 }
        let front = tabs.selected
        pull(tabs, .tab(front), from: CGPoint(x: 60, y: 16), to: CGPoint(x: 110, y: 400))
        #expect(tabs.drop == nil && tabs.dragging.lifted)
        tabs.dragging.ended(.tab(front), location: CGPoint(x: 110, y: 400))
        #expect(opened == 1 && tabs.count == 1 && !tabs.ids.contains(front))
    }

    @Test func aPaneDraggedOffItsTabBecomesATab() throws {
        let tabs = window([grades, people])
        tabs.dragging.find = { [weak tabs] in (tabs?.dragging, $0) }
        let front = tabs.selected
        let panes = try #require(tabs.front)
        panes.openBeside(codes)
        let pane = panes.ids[1]

        drop(tabs, .pane(pane, of: front), from: CGPoint(x: 60, y: 16), to: CGPoint(x: 100, y: 20))
        #expect(panes.count == 2 && tabs.count == 2)

        drop(tabs, .pane(pane, of: front), from: CGPoint(x: 60, y: 16), to: CGPoint(x: 700, y: 400))
        #expect(panes.count == 1 && tabs.count == 3)
        #expect(tabs.ids[1] == tabs.selected && tabs.current.current == codes)
    }

    // 마디를 끌면 그 마디를 담은 앞 탭 캡슐의 끌기도 함께 불린다. 두 순서 모두에서 마디만 떨어져야 한다.
    @Test func aPaneDragWinsOverItsOwnTabsDrag() throws {
        for tabFirst in [true, false] {
            let tabs = window([grades, people, settings])
            tabs.dragging.find = { [weak tabs] in (tabs?.dragging, $0) }
            var opened = 0
            tabs.dragging.openWindow = { _ in opened += 1 }
            let front = tabs.selected
            let order = tabs.ids
            let panes = try #require(tabs.front)
            panes.openBeside(codes)
            let pane = panes.ids[1]
            let from = CGPoint(x: 60, y: 16)
            func both(_ to: CGPoint) {
                let calls: [TabDrop.Item] = tabFirst ? [.tab(front), .pane(pane, of: front)] : [.pane(pane, of: front), .tab(front)]
                for item in calls { tabs.dragging.changed(item, location: to, start: from, translation: to.x - from.x) }
            }
            both(CGPoint(x: 64, y: 16))
            both(CGPoint(x: 330, y: 16))
            #expect(tabs.ids == order && tabs.dragging.dragged == .pane(pane, of: front))
            both(CGPoint(x: 700, y: 400))
            let end = CGPoint(x: 700, y: 400)
            let ends: [TabDrop.Item] = tabFirst ? [.tab(front), .pane(pane, of: front)] : [.pane(pane, of: front), .tab(front)]
            for item in ends {
                tabs.dragging.ended(item, location: end)
                tabs.dragging.cancel(item)
            }
            #expect(opened == 0 && tabs.count == 4 && panes.count == 1 && tabs.current.current == codes)
            #expect(tabs.dragging.dragged == nil)
        }
    }

    @Test func aPaneDroppedOnTheStripLandsWhereItWasDropped() throws {
        let tabs = window([grades, people, settings])
        tabs.dragging.find = { [weak tabs] in (tabs?.dragging, $0) }
        let front = tabs.selected
        let panes = try #require(tabs.front)
        panes.openBeside(codes)
        let pane = panes.ids[1]
        pull(tabs, .pane(pane, of: front), from: CGPoint(x: 60, y: 16), to: CGPoint(x: 330, y: 16))
        #expect(tabs.dragging.caret == 384)
        tabs.dragging.ended(.pane(pane, of: front), location: CGPoint(x: 330, y: 16))
        #expect(tabs.count == 4 && tabs.ids[3] == tabs.selected && tabs.current.current == codes)
    }

    @Test func withoutNewWindowsATabDroppedAwayStays() {
        let tabs = window([grades, people])
        let area = tabs.dragging.area
        let away = CGPoint(x: 700, y: 400)
        #expect(
            TabDrop.resolve(.tab(tabs.ids[1]), at: away, in: area, merge: { _ in nil }, source: true, sourceTabs: 2, tears: true)
                == .newWindow)
        #expect(
            TabDrop.resolve(.tab(tabs.ids[1]), at: away, in: area, merge: { _ in nil }, source: true, sourceTabs: 2, tears: false) == .none)
        #expect(
            TabDrop.resolve(.tab(tabs.ids[1]), at: away, in: nil, merge: { _ in nil }, source: true, sourceTabs: 1, tears: true) == .none)
    }

    @Test func theStripReachesALittleAboveAndBelowItself() {
        let tabs = window([grades, people])
        let area = tabs.dragging.area
        let item = TabDrop.Item.tab(tabs.ids[1])
        func at(_ y: CGFloat) -> TabDrop {
            TabDrop.resolve(item, at: CGPoint(x: 150, y: y), in: area, merge: { _ in nil }, source: true, sourceTabs: 2, tears: true)
        }
        #expect(at(8 + 32 + TabDrop.reach) == .strip(0))
        #expect(at(8 + 32 + TabDrop.reach + 1) == .newWindow)
        #expect(at(8 - TabDrop.reach) == .strip(0))
    }
}
