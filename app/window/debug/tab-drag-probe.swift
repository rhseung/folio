#if DEBUG && os(macOS)
import AppKit
import FolioDomain
import SwiftUI

// 합성한 포인터 사건으로는 SwiftUI의 `DragGesture`가 불리지 않아, 제스처가 부르는 끌기 모델을 직접 움직여 끄는 중인 모습을 찍는다.
@MainActor enum TabDragProbe {
    static let folder = ProcessInfo.processInfo.environment["FOLIO_TAB_DRAG"].map { URL(filePath: $0, directoryHint: .isDirectory) }

    static func run(tabs: WindowTabs, workspace: Workspace) async {
        guard let folder else { return }
        // folio:not-an-action debug screenshots, outside the GIST folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for _ in 0..<20 where workspace.currentCourses.isEmpty { try? await Task.sleep(for: .seconds(0.5)) }
        PaneBundleProbe.resize(width: SnapshotDriver.width)
        let courses = workspace.currentCourses.prefix(2).map { Navigator.Entry(link: .course($0.id), course: $0.id) }
        for entry in courses + [Navigator.Entry(link: .place(.grades))] { tabs.open(Navigator(entry)) }
        tabs.select(tabs.ids[0])
        let drag = tabs.dragging
        drag.find = { [weak drag] in (drag, $0) }
        try? await Task.sleep(for: .seconds(2))

        func local(_ global: CGPoint) -> CGPoint { CGPoint(x: global.x - drag.strip.minX, y: global.y - drag.strip.minY) }
        func hold(_ item: TabDrop.Item, from: CGPoint, to: CGPoint, _ name: String) async {
            drag.changed(item, location: from, start: from, translation: 0)
            drag.changed(item, location: to, start: from, translation: to.x - from.x)
            try? await Task.sleep(for: .seconds(1.5))
            PaneBundleProbe.capture(folder.appending(path: "\(name).png"))
        }
        func center(_ id: UUID) -> CGPoint {
            let frame = drag.frames[id] ?? .zero
            return CGPoint(x: frame.midX, y: frame.midY)
        }

        let second = tabs.ids[1]
        let start = center(second)
        let last = drag.frames[tabs.ids[3]] ?? .zero
        await hold(.tab(second), from: start, to: CGPoint(x: last.midX + Theme.Space.s, y: start.y), "1-reorder")
        drag.finish()

        let content = tabs.contentFrame
        let third = tabs.ids[2]
        await hold(.tab(third), from: center(third), to: local(CGPoint(x: content.maxX - Theme.Space.xl, y: content.midY)), "2-merge")
        drag.finish()

        await hold(.tab(third), from: center(third), to: local(CGPoint(x: content.midX, y: content.midY)), "3-tear")
        drag.finish()

        tabs.merge(third, into: tabs.selected, at: .trailing)
        try? await Task.sleep(for: .seconds(1.5))
        PaneBundleProbe.capture(folder.appending(path: "4-merged.png"))

        if let front = tabs.front, front.count > 1 {
            let pane = front.ids[1]
            let end = drag.frames[tabs.ids.last ?? second] ?? .zero
            await hold(.pane(pane, of: tabs.selected), from: center(tabs.selected), to: CGPoint(x: end.maxX, y: end.midY), "5-pane-out")
            drag.ended(.pane(pane, of: tabs.selected), location: CGPoint(x: end.maxX, y: end.midY))
            try? await Task.sleep(for: .seconds(1.5))
            PaneBundleProbe.capture(folder.appending(path: "6-pane-tab.png"))
        }
        PaneBundleProbe.quit()
    }
}
#endif
