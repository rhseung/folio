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
    /// How each pane shows its note, which only what remembers the layout reads.
    private(set) var noteModes: [NoteViewMode?] = [nil]
    /// The row's width, which the row sets every frame of a resize; read only through `fold`.
    @ObservationIgnored private var width: Double?
    /// Which panes the row keeps in place and which it bundles at its ends (`PaneLayout.fold`), from its width and
    /// the presses alone (2026-11-12 사용자). Set only when that changes, so a live resize sets it a few times, not
    /// every frame.
    private(set) var fold: PaneLayout.Fold
    /// The panes' widths moving (`PaneGlide`), which the panes' stack and the screens' widths alone read.
    private(set) var glide: PaneGlide?

    /// `columns`: a pane moved out to a tab of its own keeps them; a new tab starts from the last choice.
    init(_ navigator: Navigator, columns: ColumnPrefs? = nil, memory: ColumnMemory = .shared) {
        let layout = PaneLayout(navigator.current.link)
        self.layout = layout
        fold = layout.unfolded
        ids = [UUID()]
        navigators = [navigator]
        trails = [CrumbTrail()]
        self.columns = [columns ?? memory.newPane()]
        self.memory = memory
    }

    /// A tab moved to a window of its own: its panes go on from where they were, back and forward included, and with
    /// the columns each had hidden (`WindowRequest.columns`; nil for panes opened anew). Nil without a history.
    init?(
        histories: [LinkHistory<Navigator.Entry>], shares: [Double]?, focus: Int, columns: [[String]]? = nil,
        memory: ColumnMemory = .shared
    ) {
        guard var layout = PaneLayout(links: histories.map(\.current.link), shares: shares) else { return nil }
        layout.press(min(max(focus, 0), histories.count - 1))
        self.layout = layout
        fold = layout.unfolded
        ids = histories.map { _ in UUID() }
        navigators = histories.map(Navigator.init(history:))
        trails = histories.map { _ in CrumbTrail() }
        self.columns = histories.indices.map { i in memory.pane(columns.flatMap { $0.indices.contains(i) ? $0[i] : nil }) }
        self.memory = memory
        publish()
    }

    /// A tab laid out as `layout` was left, note modes and folds included (a class's layout, #62), each pane a history
    /// of its own at `entries`, which go with the layout's panes. Nil when they don't.
    init?(layout: PaneLayout, entries: [Navigator.Entry], memory: ColumnMemory = .shared) {
        guard entries.count == layout.panes.count else { return nil }
        self.layout = layout
        fold = layout.unfolded
        ids = entries.map { _ in UUID() }
        navigators = entries.map { Navigator($0) }
        trails = entries.map { _ in CrumbTrail() }
        columns = entries.map { _ in memory.newPane() }
        self.memory = memory
        publish()
    }

    var count: Int { ids.count }

    /// The layout with the links each pane's history has gone on to, as it is remembered.
    var current: PaneLayout {
        follow()
        return layout
    }

    /// A tab of one pane opening a class's note becomes the class's layout as it was last left (#62,
    /// `PaneMemory.restoring`). The pane goes on to the note with its history, screen and columns, in the layout's
    /// focused pane; the others open beside it, each from `entries`, where a nil is an item gone and its pane is left
    /// out. False, and nothing changed, for a tab of more panes or a layout left with one.
    @discardableResult
    func restore(_ saved: PaneLayout, entries: [Navigator.Entry?]) -> Bool {
        guard count == 1, entries.count == saved.panes.count, let entry = entries[saved.focus],
            let kept = saved.keeping({ entries[$0] != nil }), kept.panes.count > 1
        else { return false }
        let found = entries.compactMap { $0 }
        let at = kept.focus
        let navigator = navigators[0], id = ids[0], trail = trails[0], column = columns[0]
        navigator.go(entry)
        navigators = found.indices.map { $0 == at ? navigator : Navigator(found[$0]) }
        ids = found.indices.map { $0 == at ? id : UUID() }
        trails = found.indices.map { $0 == at ? trail : CrumbTrail() }
        columns = found.indices.map { $0 == at ? column : memory.newPane() }
        layout = kept
        publish()
        return true
    }

    /// A layout chosen from "배치 ▸" (#62, 2026-11-11 사용자): the tab becomes it, each pane from `entries` (a nil is
    /// an item gone, its pane left out). A pane already showing one of the addresses keeps its history, screen and
    /// columns there, and the pane in focus stays in focus if it is kept. False, and nothing changed, when no pane is
    /// left.
    @discardableResult
    func lay(_ new: PaneLayout, entries: [Navigator.Entry?]) -> Bool {
        guard entries.count == new.panes.count, var kept = new.keeping({ entries[$0] != nil }) else { return false }
        follow()
        let focused = navigators[focus]
        var free = Array(navigators.indices)
        var next: (navigators: [Navigator], ids: [UUID], trails: [CrumbTrail], columns: [ColumnPrefs]) = ([], [], [], [])
        for entry in entries.compactMap({ $0 }) {
            if let j = free.first(where: { navigators[$0].current.link.withoutAnchor == entry.link.withoutAnchor }) {
                free.removeAll { $0 == j }
                next.navigators.append(navigators[j])
                next.ids.append(ids[j])
                next.trails.append(trails[j])
                next.columns.append(columns[j])
            } else {
                next.navigators.append(Navigator(entry))
                next.ids.append(UUID())
                next.trails.append(CrumbTrail())
                next.columns.append(memory.newPane())
            }
        }
        if let i = next.navigators.firstIndex(where: { $0 === focused }) { kept.press(i) }
        (navigators, ids, trails, columns) = next
        layout = kept
        publish()
        return true
    }

    /// How pane `pane` last showed the note or text file `item`, while it still shows it.
    func noteMode(of item: UUID, pane: UUID) -> NoteViewMode? {
        guard let i = ids.firstIndex(of: pane) else { return nil }
        follow()
        return layout.panes[i].link.id == item ? layout.panes[i].noteMode : nil
    }

    /// Pane `pane` shows the note or text file `item` as `mode`, which its layout keeps (`PaneLayout.Pane.noteMode`), so
    /// a class's layout brings the note back the way it was left.
    func show(_ mode: NoteViewMode, of item: UUID, pane: UUID) {
        guard let i = ids.firstIndex(of: pane) else { return }
        follow()
        guard layout.panes[i].link.id == item, layout.panes[i].noteMode != mode else { return }
        layout.show(mode, in: i)
        publish()
    }

    /// The panes not drawn open: folded by hand, or in a bundle for want of room.
    var folded: Set<Int> { fold.folded }

    func measure(_ width: Double) {
        self.width = width
        refold()
    }

    // Before the row is first measured every pane is in place, as a tab moved to a new window was drawn.
    private func refold() {
        let new =
            width.map { layout.fold(room: $0, minWidth: Theme.Size.paneMin, strip: Theme.Size.paneStrip, gap: PaneRow.gap) }
            ?? layout.unfolded
        if fold != new { fold = new }
    }

    func canCollapse(_ i: Int) -> Bool { layout.canCollapse(i) }

    var focused: Navigator { navigators[focus] }
    var focusedTrail: CrumbTrail { trails[focus] }

    func index(of navigator: Navigator) -> Int? { navigators.firstIndex { $0 === navigator } }

    func press(_ i: Int) {
        // The focused pane is always the one pressed last, so pressing it again changes nothing.
        guard i != focus, ids.indices.contains(i) else { return }
        moving { layout.press(i) }
    }

    /// "옆 칸에 열기" from the pane showing `navigator` (the focused one without it): a new pane right of it, or the
    /// pane already showing it (`PaneLayout.openBeside`).
    func openBeside(_ entry: Navigator.Entry, from navigator: Navigator? = nil) {
        if let navigator, let i = index(of: navigator) { press(i) }
        follow()
        let before = layout.panes.count
        layout.openBeside(entry.link)
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

    /// "옆 칸으로 합치기": another tab's panes join these before pane `index` (`PaneLayout.merge`), each with its
    /// history, so back and forward go on in it as they did there. Any tab joins, however many panes either has. The
    /// other tab is left as it was, for its window to close.
    @discardableResult
    func merge(_ other: TabPanes, at index: Int) -> Bool {
        guard other !== self else { return false }
        follow()
        other.follow()
        let at = min(max(index, 0), count)
        layout.merge(other.layout, at: at)
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
        let before = fold
        change()
        #if os(macOS)
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #else
        let reduced = UIAccessibility.isReduceMotionEnabled
        #endif
        // The fold first: it is what the glide moves to.
        refold()
        if !reduced, from.panes.count == layout.panes.count, from.shares != layout.shares || before != fold {
            let glide = PaneGlide(from: from, fold: before)
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
        refold()
        if focus != layout.focus { focus = layout.focus }
        if shares != layout.shares { shares = layout.shares }
        if collapsed != layout.collapsed { collapsed = layout.collapsed }
        let modes = layout.panes.map(\.noteMode)
        if noteModes != modes { noteModes = modes }
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
    static let spring = Theme.Motion.paneSpring

    let from: PaneLayout
    let fold: PaneLayout.Fold
    let start = Date()
    private let id = UUID()

    init(from: PaneLayout, fold: PaneLayout.Fold) {
        self.from = from
        self.fold = fold
    }

    /// How far along at `date`, 0 to 1, on `Theme.Motion.paneSpring`; whole once the spring has settled.
    func progress(at date: Date) -> Double {
        let t = date.timeIntervalSince(start)
        return t >= Self.duration ? 1 : min(1, max(0, Self.spring.value(target: 1.0, time: t)))
    }
}

extension Workspace {
    /// The class a tab's panes are about, to fill a layout's roles from (`PaneLayout.lesson`).
    func lesson(of panes: TabPanes) -> (course: UUID, session: Session)? {
        panes.current.lesson(in: courses.map(\.file), now: liveNow)
    }

    /// The layout, built-in or the user's, a tab's panes are laid out as (`PanePreset.matching`); nil for a tab of
    /// one pane, and for an arrangement of the user's own that isn't saved.
    func preset(of panes: TabPanes) -> PanePreset? {
        guard panes.count > 1 else { return nil }
        let course = lesson(of: panes)?.course ?? panes.navigators.lazy.compactMap(\.current.course).first
        return PanePreset.matching(panes.current, among: settings.presets, in: course.flatMap { self.course($0) }?.file)
    }

    func presetName(of panes: TabPanes) -> String? { preset(of: panes)?.title }

    /// What `preset` turns the tab into: its roles filled from the tab's class, its addresses as they are. Nil when
    /// it has nothing to show there (a layout with a role, in a tab of no class).
    func layout(_ preset: PanePreset, for panes: TabPanes) -> PaneLayout? {
        let lesson = lesson(of: panes)
        return preset.layout(session: lesson?.session, course: lesson?.course)
    }

    func apply(_ preset: PanePreset, to panes: TabPanes) {
        guard let layout = layout(preset, for: panes) else { return }
        let hint = lesson(of: panes)?.course ?? panes.focused.current.course
        panes.lay(layout, entries: layout.panes.map { entry(for: $0.link, hint: hint) })
    }

    /// "지금 배치 저장…": the tab's panes kept under `name` after the user's other layouts.
    func saveLayout(of panes: TabPanes, name: String) {
        let lesson = lesson(of: panes)
        var new = settings
        new.panePresets.append(.saving(panes.current, name: name, session: lesson?.session, course: lesson?.course))
        saveSettings(new)
    }

    var newPresetName: String {
        PanePreset.freeName(String(localized: .panesPresetsNewName), taken: settings.presets.map(\.title))
    }
}

extension PanePreset {
    var title: String {
        if let name { return name }
        return switch id {
        case PanePreset.inClass.id: String(localized: .panesPresetInClass)
        case PanePreset.review.id: String(localized: .panesPresetReview)
        default: id
        }
    }

    var symbol: String { slots.count >= 3 ? "rectangle.split.3x1" : "rectangle.split.2x1" }
}

extension PanePreset.Role {
    var label: String {
        switch self {
        case .lecture: String(localized: .panesRoleLecture)
        case .classNote: String(localized: .panesRoleClassNote)
        case .reviewNote: String(localized: .panesRoleReviewNote)
        case .quiz: String(localized: .panesRoleQuiz)
        }
    }
}
