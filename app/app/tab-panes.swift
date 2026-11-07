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
    private(set) var focus = 0
    /// Read only by the panes' row.
    private(set) var shares: [Double] = [1]
    let limit: Int

    static var limit: Int {
        #if os(macOS)
        PaneLayout.Device.mac.maxPanes
        #else
        PaneLayout.Device.pad.maxPanes
        #endif
    }

    init(_ navigator: Navigator, limit: Int = TabPanes.limit) {
        layout = PaneLayout(navigator.current.link)
        ids = [UUID()]
        navigators = [navigator]
        trails = [CrumbTrail()]
        self.limit = limit
    }

    /// A tab moved to a window of its own: its panes go on from where they were, back and forward included. Nil
    /// without a history.
    init?(histories: [LinkHistory<Navigator.Entry>], shares: [Double]?, focus: Int, limit: Int = TabPanes.limit) {
        let histories = Array(histories.prefix(max(1, limit)))
        guard var layout = PaneLayout(links: histories.map(\.current.link), shares: shares, limit: limit) else { return nil }
        layout.press(min(max(focus, 0), histories.count - 1))
        self.layout = layout
        ids = histories.map { _ in UUID() }
        navigators = histories.map(Navigator.init(history:))
        trails = histories.map { _ in CrumbTrail() }
        self.limit = limit
        publish()
    }

    var count: Int { ids.count }
    var focused: Navigator { navigators[focus] }
    var focusedTrail: CrumbTrail { trails[focus] }

    func index(of navigator: Navigator) -> Int? { navigators.firstIndex { $0 === navigator } }

    /// A click anywhere in pane `i`, or on its strip or segment.
    func press(_ i: Int) {
        // The focused pane is always the one pressed last, so pressing it again changes nothing.
        guard i != focus, ids.indices.contains(i) else { return }
        layout.press(i)
        publish()
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
        } else {
            navigators[layout.focus].go(entry)
        }
        publish()
    }

    /// False, and nothing closed, for the last pane: closing it is closing the tab.
    @discardableResult
    func close(_ i: Int) -> Bool {
        guard layout.close(i) else { return false }
        ids.remove(at: i)
        navigators.remove(at: i)
        trails.remove(at: i)
        publish()
        return true
    }

    func swap(_ i: Int, _ j: Int) {
        guard ids.indices.contains(i), ids.indices.contains(j), i != j else { return }
        layout.swap(i, j)
        ids.swapAt(i, j)
        navigators.swapAt(i, j)
        trails.swapAt(i, j)
        publish()
    }

    func resize(divider: Int, to fraction: Double) {
        layout.resize(divider: divider, to: fraction)
        publish()
    }

    /// The links each pane's history went on to since; the layout keeps them only for what compares them.
    private func follow() {
        for (i, navigator) in navigators.enumerated() { layout.open(navigator.current.link, in: i) }
    }

    private func publish() {
        if focus != layout.focus { focus = layout.focus }
        if shares != layout.shares { shares = layout.shares }
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
