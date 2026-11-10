import FolioDomain
import SwiftUI

/// One tab's panes (#62), left to right. Each pane has a history of its own and the breadcrumb steps its screen adds;
/// the layout says how wide each is, which one is focused and which fold first. The tab's breadcrumb, back and forward
/// follow the focused pane.
@MainActor @Observable
final class TabPanes {
    /// Not watched as a whole: a drag on a divider changes it every frame, and the toolbar's tabs, which draw from the
    /// focus and the panes, would redraw with it (each redraw rebuilds the toolbar's menu form, #310). What views draw
    /// from is copied out below, each only when it changes.
    @ObservationIgnored private(set) var layout: PaneLayout
    private(set) var ids: [UUID]
    private(set) var navigators: [Navigator]
    private(set) var trails: [CrumbTrail]
    /// The list columns each pane has hidden by hand: its own, which a new pane starts from the last choice
    /// (2026-11-10 사용자).
    private(set) var columns: [ColumnPrefs]
    @ObservationIgnored private let memory: ColumnMemory
    private(set) var focus = 0
    /// Read only by the panes' row.
    private(set) var shares: [Double] = [1]
    /// The panes folded by hand (`collapse`).
    private(set) var collapsed: Set<Int> = []
    /// How many panes the row has room to keep open with two panes and with three (`PaneLayout.openCount`). The row
    /// sets it only where its width crosses a count, so a live resize sets it a few times, not every frame.
    var room = [2, 3]
    /// The panes' widths moving (`PaneGlide`), which the panes' stack and the screens' widths alone read.
    private(set) var glide: PaneGlide?
    let limit: Int

    static var limit: Int {
        #if os(macOS)
        PaneLayout.Device.mac.maxPanes
        #else
        PaneLayout.Device.pad.maxPanes
        #endif
    }

    /// `columns`: a pane moved out to a tab of its own keeps them; a new tab starts from the last choice.
    init(_ navigator: Navigator, columns: ColumnPrefs? = nil, limit: Int = TabPanes.limit, memory: ColumnMemory = .shared) {
        layout = PaneLayout(navigator.current.link)
        ids = [UUID()]
        navigators = [navigator]
        trails = [CrumbTrail()]
        self.columns = [columns ?? memory.newPane()]
        self.memory = memory
        self.limit = limit
    }

    /// A tab moved to a window of its own: its panes go on from where they were, back and forward included, and with
    /// the columns each had hidden (`WindowRequest.columns`; nil for panes opened anew). Nil without a history.
    init?(histories: [LinkHistory<Navigator.Entry>], shares: [Double]?, focus: Int, columns: [[String]]? = nil,
          limit: Int = TabPanes.limit, memory: ColumnMemory = .shared) {
        let histories = Array(histories.prefix(max(1, limit)))
        guard var layout = PaneLayout(links: histories.map(\.current.link), shares: shares, limit: limit) else { return nil }
        layout.press(min(max(focus, 0), histories.count - 1))
        self.layout = layout
        ids = histories.map { _ in UUID() }
        navigators = histories.map(Navigator.init(history:))
        trails = histories.map { _ in CrumbTrail() }
        self.columns = histories.indices.map { i in memory.pane(columns.flatMap { $0.indices.contains(i) ? $0[i] : nil }) }
        self.memory = memory
        self.limit = limit
        publish()
    }

    var count: Int { ids.count }

    /// The panes drawn as strips: folded by hand, or for want of room.
    var folded: Set<Int> {
        // The layout isn't watched: what it is published as is, so a reader redraws when a press or a fold moves it.
        _ = (focus, collapsed)
        return count > 1 ? layout.folded(open: room[min(count, 3) - 2]) : []
    }

    func canCollapse(_ i: Int) -> Bool { layout.canCollapse(i) }

    var focused: Navigator { navigators[focus] }
    var focusedTrail: CrumbTrail { trails[focus] }

    func index(of navigator: Navigator) -> Int? { navigators.firstIndex { $0 === navigator } }

    /// A click anywhere in pane `i`, or on its strip or segment.
    func press(_ i: Int) {
        // The focused pane is always the one pressed last, so pressing it again changes nothing.
        guard i != focus, ids.indices.contains(i) else { return }
        moving { layout.press(i) }
    }

    /// "옆 칸에 열기" from the pane showing `navigator` (the focused one without it): a new pane right of it while
    /// there is room for one, else the pane used longest ago, or the pane already showing it (`PaneLayout.openBeside`).
    func openBeside(_ entry: Navigator.Entry, from navigator: Navigator? = nil) {
        if let navigator, let i = index(of: navigator) { press(i) }
        follow()
        let before = layout.panes.count
        layout.openBeside(entry.link, limit: limit)
        if layout.panes.count > before {
            let i = layout.focus
            ids.insert(UUID(), at: i)
            navigators.insert(Navigator(entry), at: i)
            trails.insert(CrumbTrail(), at: i)
            columns.insert(memory.newPane(), at: i)
        } else {
            navigators[layout.focus].go(entry)
        }
        publish()
    }

    func canMerge(_ other: TabPanes) -> Bool { other !== self && layout.canMerge(other.layout, limit: limit) }

    /// "옆 칸으로 합치기": another tab's panes join these before pane `index` (`PaneLayout.merge`), each with its
    /// history, so back and forward go on in it as they did there. False, and nothing taken, past the limit. The
    /// other tab is left as it was, for its window to close.
    @discardableResult
    func merge(_ other: TabPanes, at index: Int) -> Bool {
        guard other !== self else { return false }
        follow()
        other.follow()
        let at = min(max(index, 0), count)
        guard layout.merge(other.layout, at: at, limit: limit) else { return false }
        // New IDs and trails: the panes' screens are drawn anew in this tab, and a playing pane's old screen says it
        // stopped by its old ID as it goes.
        ids.insert(contentsOf: other.ids.map { _ in UUID() }, at: at)
        navigators.insert(contentsOf: other.navigators, at: at)
        trails.insert(contentsOf: other.ids.map { _ in CrumbTrail() }, at: at)
        // Each pane keeps the columns it had hidden in its tab, as it keeps its history.
        columns.insert(contentsOf: other.columns, at: at)
        publish()
        return true
    }

    /// False, and nothing closed, for the last pane: closing it is closing the tab.
    @discardableResult
    func close(_ i: Int) -> Bool {
        guard layout.close(i) else { return false }
        ids.remove(at: i)
        navigators.remove(at: i)
        trails.remove(at: i)
        columns.remove(at: i)
        publish()
        return true
    }

    /// By the pane's ID, for what draws a pane apart from the row's order: a place kept from before a pane closed is
    /// another pane's now, or past the end.
    func press(pane id: UUID) {
        if let i = ids.firstIndex(of: id) { press(i) }
    }

    @discardableResult
    func close(pane id: UUID) -> Bool {
        ids.firstIndex(of: id).map { close($0) } ?? false
    }

    func swap(_ i: Int, _ j: Int) {
        guard ids.indices.contains(i), ids.indices.contains(j), i != j else { return }
        layout.swap(i, j)
        ids.swapAt(i, j)
        navigators.swapAt(i, j)
        trails.swapAt(i, j)
        columns.swapAt(i, j)
        publish()
    }

    func resize(divider: Int, to fraction: Double) {
        layout.resize(divider: divider, to: fraction)
        publish()
    }

    /// 칸 접기: pane `i` a strip at any width until it is pressed (`PaneLayout.collapse`).
    func collapse(_ i: Int) { moving { layout.collapse(i) } }

    /// 칸 폭 맞추기, from a divider or the 보기 menu: every pane as wide as the others.
    func even() { moving { layout.even() } }

    /// A change to the layout that moves a pane's edge (a strip opening or folding, the widths evened) glides there
    /// unless the system asks for less motion. Read from the system, not the environment: the menu bar's commands
    /// have none.
    private func moving(_ change: () -> Void) {
        let from = layout
        let folded = folded
        change()
        #if os(macOS)
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #else
        let reduced = UIAccessibility.isReduceMotionEnabled
        #endif
        if !reduced, from.panes.count == layout.panes.count, from.shares != layout.shares || folded != self.folded {
            let glide = PaneGlide(from: from, folded: folded)
            self.glide = glide
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(PaneGlide.duration))
                if self?.glide == glide { self?.glide = nil }
            }
        }
        publish()
    }

    /// The links each pane's history went on to since; the layout keeps them only for what compares them.
    private func follow() {
        for (i, navigator) in navigators.enumerated() { layout.open(navigator.current.link, in: i) }
    }

    private func publish() {
        if focus != layout.focus { focus = layout.focus }
        if shares != layout.shares { shares = layout.shares }
        if collapsed != layout.collapsed { collapsed = layout.collapsed }
    }
}

/// Panes moving to new widths a frame at a time, from the layout and strips they had. Not an animation of the widths:
/// under one, each pane's screen animated its own new layout as well, and a lazy page (the course overview) slid its
/// rows and scroll offset about and bounced (2026-11-08 사용자); a pane widening laid its screen out at the end width
/// at once, over the pane beside it. Stepped like a divider's drag, each frame lays an open pane's screen out at that
/// frame's width with nothing inside it animated; a pane folding or opening keeps its screen at its open width, its
/// panel's edge sliding over it.
struct PaneGlide: Equatable {
    static let duration = 0.5
    static let spring = Spring.smooth(duration: 0.34)

    let from: PaneLayout
    let folded: Set<Int>
    let start = Date()
    private let id = UUID()

    init(from: PaneLayout, folded: Set<Int>) {
        self.from = from
        self.folded = folded
    }

    /// How far along at `date`, 0 to 1, on the curve 0.34s `.smooth` takes; whole once the spring has settled.
    func progress(at date: Date) -> Double {
        let t = date.timeIntervalSince(start)
        return t >= Self.duration ? 1 : min(1, max(0, Self.spring.value(target: 1.0, time: t)))
    }
}

extension Workspace {
    /// The built-in preset a tab's panes are laid out as, by its name (`PanePreset.matching` against the sessions of
    /// the course they show); nil for a layout of the user's own.
    func presetName(of panes: TabPanes) -> String? {
        guard panes.count > 1, let course = panes.navigators.lazy.compactMap(\.current.course).first, let file = self.course(course)?.file,
              let layout = PaneLayout(links: panes.navigators.map(\.current.link), limit: panes.limit) else { return nil }
        return file.sessions.lazy.compactMap { PanePreset.matching(layout, session: $0, course: course, limit: panes.limit) }.first?.name
    }
}

extension PanePreset {
    var name: String {
        switch id {
        case PanePreset.inClass.id: String(localized: .panesPresetInClass)
        case PanePreset.concepts.id: String(localized: .panesPresetConcepts)
        case PanePreset.problems.id: String(localized: .panesPresetProblems)
        case PanePreset.review.id: String(localized: .panesPresetReview)
        default: id
        }
    }
}
