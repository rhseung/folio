import FolioDomain
import SwiftUI

@MainActor @Observable
final class TabPanes {
    // 통째로 관찰하지 않는다. 구분선 drag가 frame마다 값을 바꾸면 초점과 칸에서 그리는 툴바의 탭이 함께 다시 그려지고,
    // 다시 그릴 때마다 툴바의 메뉴를 새로 만든다. 뷰가 그리는 값은 아래에 따로 복사하고, 바뀔 때만 고친다.
    @ObservationIgnored private(set) var layout: PaneLayout
    private(set) var ids: [UUID]
    private(set) var navigators: [Navigator]
    private(set) var trails: [CrumbTrail]
    private(set) var columns: [ColumnPrefs]
    @ObservationIgnored private let memory: ColumnMemory
    private(set) var focus = 0
    private(set) var shares: [Double] = [1]
    private(set) var collapsed: Set<Int> = []
    private(set) var noteModes: [NoteViewMode?] = [nil]
    @ObservationIgnored private var width: Double?
    private(set) var fold: PaneLayout.Fold
    private(set) var glide: PaneGlide?

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

    var current: PaneLayout {
        follow()
        return layout
    }

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

    func noteMode(of item: UUID, pane: UUID) -> NoteViewMode? {
        guard let i = ids.firstIndex(of: pane) else { return nil }
        follow()
        return layout.panes[i].link.id == item ? layout.panes[i].noteMode : nil
    }

    func show(_ mode: NoteViewMode, of item: UUID, pane: UUID) {
        guard let i = ids.firstIndex(of: pane) else { return }
        follow()
        guard layout.panes[i].link.id == item, layout.panes[i].noteMode != mode else { return }
        layout.show(mode, in: i)
        publish()
    }

    var folded: Set<Int> { fold.folded }

    func measure(_ width: Double) {
        self.width = width
        refold()
    }

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
        guard i != focus, ids.indices.contains(i) else { return }
        moving { layout.press(i) }
    }

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

    @discardableResult
    func merge(_ other: TabPanes, at index: Int) -> Bool {
        guard other !== self else { return false }
        follow()
        other.follow()
        let at = min(max(index, 0), count)
        layout.merge(other.layout, at: at)
        // 칸들은 이 탭에서 화면을 새로 그리므로 새 ID와 trail을 받는다. 재생 중인 칸의 이전 화면은 사라지면서 이전 ID로 멈췄다고
        // 알린다.
        ids.insert(contentsOf: other.ids.map { _ in UUID() }, at: at)
        navigators.insert(contentsOf: other.navigators, at: at)
        trails.insert(contentsOf: other.ids.map { _ in CrumbTrail() }, at: at)
        columns.insert(contentsOf: other.columns, at: at)
        publish()
        return true
    }

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

    // 칸이 닫히기 전에 기억한 자리는 이제 다른 칸의 자리이거나 끝을 넘으므로, 행의 순서와 따로 칸을 그리는 곳은 ID로 누른다.
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

    func collapse(_ i: Int) { moving { layout.collapse(i) } }

    func even() { moving { layout.even() } }

    // 환경값이 아니라 시스템에서 읽는다. 메뉴 막대의 명령에는 환경값이 없기 때문이다.
    private func moving(_ change: () -> Void) {
        let from = layout
        let before = fold
        change()
        #if os(macOS)
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #else
        let reduced = UIAccessibility.isReduceMotionEnabled
        #endif
        // glide가 향하는 곳이 fold이므로 fold를 먼저 정한다.
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

// 폭의 animation이 아니다. animation을 쓰면 칸마다 화면이 자기 새 배치도 animation 했고, 지연 페이지(과목 개요)는 행과
// scroll offset이 흔들리며 튀었다. 넓어지는 칸은 화면을 바로 끝 폭으로 배치해 옆 칸을 덮었다. 그래서 구분선 drag처럼
// 단계를 밟아, frame마다 열린 칸의 화면을 그 frame의 폭으로 배치하고 안쪽은 animation 하지 않는다. 접히거나 열리는 칸은
// 화면을 열린 폭으로 두고 패널의 가장자리만 그 위로 움직인다.
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

    func progress(at date: Date) -> Double {
        let t = date.timeIntervalSince(start)
        return t >= Self.duration ? 1 : min(1, max(0, Self.spring.value(target: 1.0, time: t)))
    }
}

extension Workspace {
    func lesson(of panes: TabPanes) -> (course: UUID, session: Session)? {
        panes.current.lesson(in: courses.map(\.file), now: liveNow)
    }

    func preset(of panes: TabPanes) -> PanePreset? {
        guard panes.count > 1 else { return nil }
        let course = lesson(of: panes)?.course ?? panes.navigators.lazy.compactMap(\.current.course).first
        return PanePreset.matching(panes.current, among: settings.presets, in: course.flatMap { self.course($0) }?.file)
    }

    func presetName(of panes: TabPanes) -> String? { preset(of: panes)?.title }

    func layout(_ preset: PanePreset, for panes: TabPanes) -> PaneLayout? {
        let lesson = lesson(of: panes)
        return preset.layout(session: lesson?.session, course: lesson?.course)
    }

    func apply(_ preset: PanePreset, to panes: TabPanes) {
        guard let layout = layout(preset, for: panes) else { return }
        let hint = lesson(of: panes)?.course ?? panes.focused.current.course
        panes.lay(layout, entries: layout.panes.map { entry(for: $0.link, hint: hint) })
    }

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
