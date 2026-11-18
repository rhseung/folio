import SwiftUI

#if os(macOS)
import AppKit
#endif

@MainActor @Observable final class TabDrag {
    unowned let tabs: WindowTabs
    // 탭 줄 공간의 자리다. 끄는 탭의 offset이 들어가지 않은, 줄이 놓은 자리여야 한다.
    @ObservationIgnored var frames: [UUID: CGRect] = [:]
    @ObservationIgnored var row: [UUID] = []
    @ObservationIgnored var strip: CGRect = .zero
    @ObservationIgnored var openWindow: (WindowRequest) -> Void = { _ in }
    // 포인터 아래의 창과 그 창 안의 자리를 찾는다. 테스트는 실제 포인터 대신 정해 둔 창을 준다.
    @ObservationIgnored var find: ((CGPoint) -> (TabDrag?, CGPoint))?
    #if os(macOS)
    @ObservationIgnored weak var window: NSWindow?
    #endif
    private(set) var dragged: TabDrop.Item?
    private(set) var offset: CGFloat = 0
    private(set) var lifted = false
    private(set) var caret: CGFloat?
    @ObservationIgnored private var start: (minX: CGFloat, grab: CGPoint)?

    #if os(macOS)
    static let tears = true
    #else
    // iPad에서 탭을 새 장면으로 떼는 일은 아직 하지 않는다(#305의 "Apple Developer 가입 뒤").
    static let tears = false
    #endif

    init(tabs: WindowTabs) {
        self.tabs = tabs
        TabDragHub.shared.register(self)
    }

    var area: TabDrop.Area {
        let origin = strip.origin
        return TabDrop.Area(
            strip: strip, row: row, frames: frames.mapValues { $0.offsetBy(dx: origin.x, dy: origin.y) }, ids: tabs.ids,
            selected: tabs.selected)
    }

    func keep(_ open: Set<UUID>) { frames = frames.filter { open.contains($0.key) } }

    func changed(_ item: TabDrop.Item, location: CGPoint, start startLocation: CGPoint, translation: CGFloat) {
        guard !yields(item), let frame = frames[item.tab] else { return }
        if dragged != item {
            dragged = item
            start = (frame.minX, global(startLocation))
        }
        let (target, point) = locate(global(location))
        let place = resolve(item, at: point, in: target)
        let caret: CGFloat? =
            if case .strip = place, let target, target !== self || isPane(item) {
                TabDrop.caret(at: point.x, in: target.area, gap: TabBar.gap).map { $0 - target.strip.minX }
            } else { nil }
        TabDragHub.shared.show(place, in: target, caret: caret)
        if case .tab(let id) = item, target === self, case .strip(let i) = place { reorder(id, to: i) }
        let staying: Bool = if target === self, case .strip = place { true } else { false }
        if lifted == staying { withAnimation(Theme.Motion.quick) { lifted = !staying } }
        offset = isPane(item) ? translation : translation - ((frames[item.tab]?.minX ?? frame.minX) - (start?.minX ?? frame.minX))
    }

    func ended(_ item: TabDrop.Item, location: CGPoint) {
        guard !yields(item) else { return }
        defer { finish() }
        guard dragged == item else { return }
        let (target, point) = locate(global(location))
        switch resolve(item, at: point, in: target) {
        case .none: break
        case .strip(let i):
            if case .tab = item, target === self { break }
            if let target { move(item, to: target) { $0.tabs.insert($1, at: i) } }
        case .merge(let drop):
            if case .tab(let id) = item, target === self {
                tabs.merge(id, into: tabs.selected, at: drop.edge)
            } else if let target {
                move(item, to: target) { $0.tabs.merge($1, at: drop.edge) }
            }
        case .newTab:
            if let panes = take(item, evenLast: false) { tabs.open(panes, fromLink: true) }
        case .newWindow:
            if let panes = take(item, evenLast: false) { openWindow(with: panes) }
        }
    }

    // 칸 마디는 앞 탭 캡슐 안에 있어 마디를 끌면 캡슐의 끌기도 함께 인식된다. 마디 끌기가 이기고, 캡슐 쪽 사건은 버린다.
    // 버리지 않으면 사건마다 끄는 것이 탭과 칸 사이를 오가며 앞 탭의 순서를 바꾸거나 탭 전체를 새 창으로 뗀다.
    private func yields(_ item: TabDrop.Item) -> Bool {
        guard case .tab(let id) = item, case .pane(_, of: let owner)? = dragged else { return false }
        return id == owner
    }

    // 다른 항목을 끄는 중이면 그 끌기를 끝내지 않는다. 제스처의 상태는 그 항목의 끌기가 끝나기 전에도 풀린다.
    func cancel(_ item: TabDrop.Item) {
        guard dragged == nil || dragged == item else { return }
        finish()
    }

    func finish() {
        TabDragHub.shared.clear()
        guard dragged != nil else { return }
        start = nil
        withAnimation(Theme.Motion.quick) {
            dragged = nil
            offset = 0
            lifted = false
        }
    }

    func preview(_ place: TabDrop, caret: CGFloat?) {
        let drop: WindowTabs.MergeDrop? = if case .merge(let drop) = place { drop } else { nil }
        if tabs.drop != drop { tabs.drop = drop }
        if self.caret != caret { self.caret = caret }
    }

    func clearPreview() {
        if tabs.drop != nil { tabs.drop = nil }
        if caret != nil { caret = nil }
    }

    func resolve(_ item: TabDrop.Item, at point: CGPoint, in target: TabDrag?) -> TabDrop {
        let count = isPane(item) ? 1 : tabs.panes(item.tab)?.count ?? 1
        return TabDrop.resolve(
            item, at: point, in: target?.area, merge: { target?.tabs.drop(adding: count, at: $0) }, source: target === self,
            sourceTabs: tabs.count, tears: Self.tears)
    }

    private func isPane(_ item: TabDrop.Item) -> Bool { if case .pane = item { true } else { false } }

    private func global(_ location: CGPoint) -> CGPoint { CGPoint(x: strip.minX + location.x, y: strip.minY + location.y) }

    // 포인터가 이 창 안에 있으면 제스처가 잰 자리를 그대로 쓴다. 화면 좌표를 거치면 반올림만큼 탭 줄의 순서가 떨린다.
    private func locate(_ point: CGPoint) -> (TabDrag?, CGPoint) {
        if let find { return find(point) }
        #if os(macOS)
        guard let found = TabDragHub.shared.target(atScreen: NSEvent.mouseLocation) else { return (nil, point) }
        return found.drag === self ? (self, point) : (found.drag, found.point)
        #else
        return (self, point)
        #endif
    }

    private func reorder(_ id: UUID, to index: Int) {
        var rest = tabs.ids.filter { $0 != id }
        rest.insert(id, at: min(index, rest.count))
        if rest != tabs.ids { tabs.move(id, to: index) }
    }

    private func take(_ item: TabDrop.Item, evenLast: Bool) -> TabPanes? {
        switch item {
        case .tab(let id): tabs.take(id, evenLast: evenLast)
        case .pane(let pane, of: let id): tabs.take(pane: pane, of: id)
        }
    }

    // 받는 창에 먼저 넣고 나서 빈 창을 닫는다.
    private func move(_ item: TabDrop.Item, to target: TabDrag, _ put: (TabDrag, TabPanes) -> Void) {
        let last: Bool = if case .tab = item { tabs.count == 1 } else { false }
        guard let panes = take(item, evenLast: true) else { return }
        put(target, panes)
        #if os(macOS)
        if target !== self { target.window?.makeKeyAndOrderFront(nil) }
        #endif
        if last { tabs.closeWindow() }
    }

    private func openWindow(with panes: TabPanes) {
        let request = WindowRequest(moving: panes)
        #if os(macOS)
        // 놓은 자리에서 잡았던 탭이 포인터 아래에 오도록, 끌기를 시작한 창 안의 자리만큼 새 창을 옮긴다.
        if let window, let grab = start?.grab {
            let mouse = NSEvent.mouseLocation
            let size = window.frame.size
            TabDragHub.shared.place(
                request.id, at: CGRect(x: mouse.x - grab.x, y: mouse.y + grab.y - size.height, width: size.width, height: size.height))
        }
        #endif
        openWindow(request)
    }
}
