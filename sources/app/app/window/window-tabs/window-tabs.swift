import FolioDomain
import SwiftUI

@MainActor @Observable
final class WindowTabs {
    private(set) var strip: TabStrip<UUID> {
        didSet {
            if oldValue.selected != strip.selected { left[oldValue.selected] = now() }
            settle()
        }
    }
    private var tabs: [UUID: TabPanes]
    private(set) var alive: Set<UUID>
    @ObservationIgnored private var left: [UUID: Date] = [:]
    private(set) var playing: Set<UUID> = []
    private(set) var playingPanes: Set<UUID> = []
    @ObservationIgnored private var pauses: [UUID: @MainActor () -> Void] = [:]
    @ObservationIgnored var closeWindow: @MainActor () -> Void = {}
    @ObservationIgnored var now: @MainActor () -> Date = { .now }
    @ObservationIgnored var policy = WindowTabs.keep
    @ObservationIgnored var contentFrame: CGRect = .zero
    var drop: MergeDrop?

    enum MergeEdge: Equatable {
        case leading, trailing
    }

    struct MergeDrop: Equatable {
        var edge: MergeEdge
        var share: Double
    }

    // 노트 탭이 가장 비싸다. 미리보기 페이지가 별도의 WebKit process에서 돌아 보통 노트는 약 80MB, 수식과 그림이 많은 긴
    // 노트는 270MB를 쓰고, 과목 페이지는 10MB를 쓴다(`TabMemoryProbe`로 쟀다).
    static let keep = TabKeep.Policy(limit: 3, idle: 30 * 60)

    convenience init(_ first: Navigator) { self.init(TabPanes(first)) }

    init(_ first: TabPanes) {
        let id = UUID()
        strip = TabStrip(id)
        tabs = [id: first]
        alive = [id]
    }

    var selected: UUID { strip.selected }
    var ids: [UUID] { strip.tabs }
    var count: Int { strip.tabs.count }
    var current: Navigator { tabs[strip.selected]?.focused ?? Navigator() }
    var front: TabPanes? { tabs[strip.selected] }

    func panes(_ id: UUID) -> TabPanes? { tabs[id] }
    func navigator(_ id: UUID) -> Navigator? { tabs[id]?.focused }
    func trail(_ id: UUID) -> CrumbTrail? { tabs[id]?.focusedTrail }
    func panes(holding navigator: Navigator) -> TabPanes? { tabs.values.first { $0.index(of: navigator) != nil } }

    func open(_ navigator: Navigator = Navigator(), columns: ColumnPrefs? = nil, fromLink: Bool = false) {
        open(TabPanes(navigator, columns: columns), fromLink: fromLink)
    }

    func open(_ panes: TabPanes, fromLink: Bool = false) {
        let id = UUID()
        tabs[id] = panes
        strip.open(id, afterSelected: fromLink)
    }

    func select(_ id: UUID) { strip.select(id) }
    func select(number n: Int) { strip.select(number: n) }
    func selectNext() { strip.selectNext() }
    func selectPrevious() { strip.selectPrevious() }
    func move(_ id: UUID, to index: Int) { strip.move(id, to: index) }

    func close(_ id: UUID) {
        guard strip.close(id) else { return closeWindow() }
        tabs[id] = nil
    }

    func closeSelected() { close(selected) }

    func play(_ id: UUID, pane: UUID? = nil, pause: (@MainActor () -> Void)?) {
        if let pane = pane ?? tabs[id]?.ids.first {
            pauses[pane] = pause
            let on = pause != nil && strip.tabs.contains(id)
            if on != playingPanes.contains(pane) { if on { playingPanes.insert(pane) } else { playingPanes.remove(pane) } }
        }
        settlePlaying()
    }

    private func settlePlaying() {
        let open = Set(strip.tabs.flatMap { tabs[$0]?.ids ?? [] })
        let panes = playingPanes.intersection(open)
        if panes != playingPanes { playingPanes = panes }
        let tabs = Set(strip.tabs.filter { self.tabs[$0]?.ids.contains(where: panes.contains) == true })
        if tabs != playing { playing = tabs }
    }

    func pause(_ id: UUID) {
        for pane in tabs[id]?.ids ?? [] where playingPanes.contains(pane) { pauses[pane]?() }
    }

    func pause(pane: UUID) { pauses[pane]?() }

    func closeOthers(than id: UUID) {
        strip.closeOthers(than: id)
        tabs = tabs.filter { $0.key == id }
    }

    func canMerge(_ id: UUID, into target: UUID) -> Bool {
        id != target && tabs[id] != nil && tabs[target] != nil
    }

    func merge(_ id: UUID, into target: UUID, at edge: MergeEdge? = nil) {
        guard canMerge(id, into: target), let source = tabs[id], let into = tabs[target] else { return }
        let index =
            switch edge {
            case .leading: 0
            case .trailing: into.count
            case nil: into.focus + 1
            }
        guard into.merge(source, at: index), strip.close(id) else { return }
        tabs[id] = nil
        strip.select(target)
        settlePlaying()
    }

    func drop(for id: UUID, at point: CGPoint) -> MergeDrop? {
        let frame = contentFrame
        guard id != selected, canMerge(id, into: selected), let source = tabs[id], let front = front, frame.width > 0,
            frame.minY <= point.y, point.y <= frame.maxY
        else { return nil }
        let zone = min(Self.mergeZone, frame.width / 3)
        let edge: MergeEdge
        if point.x <= frame.minX + zone { edge = .leading } else if point.x >= frame.maxX - zone { edge = .trailing } else { return nil }
        return MergeDrop(edge: edge, share: Double(source.count) / Double(source.count + front.count))
    }

    static let mergeZone = Theme.Size.paneMin / 2

    func take(_ id: UUID) -> TabPanes? {
        guard count > 1, let panes = tabs[id], strip.close(id) else { return nil }
        tabs[id] = nil
        return panes
    }

    func tick() { settle() }

    func dropBackground() { settle(pressure: true) }

    private func settle(pressure: Bool = false) {
        left = left.filter { strip.tabs.contains($0.key) }
        let kept = TabKeep.alive(
            selected: strip.selected, alive: alive.intersection(strip.tabs), left: left, now: now(), policy: policy,
            pressure: pressure, playing: playing)
        if kept != alive { alive = kept }
    }
}

extension EnvironmentValues {
    @Entry var tabPlaying: @MainActor ((@MainActor () -> Void)?) -> Void = { _ in }
}

extension FocusedValues {
    @Entry var windowTabs: WindowTabs?
    @Entry var frontPanes: TabPanes?
}

extension Workspace {
    func placeCrumb(of entry: Navigator.Entry) -> Crumb {
        switch Screen(entry) {
        case .course(let id): Crumb(title: course(id)?.title ?? "", symbol: course(id)?.file.course.icon, dot: accent(id).color)
        case .semester(let id):
            {
                let semester = transcript.semesters.first { $0.id == id }
                return Crumb(title: semester?.title ?? "", symbol: semester?.term == .credited ? "checkmark.seal" : "folder")
            }()
        case .grades: Crumb(title: String(localized: .rootNavGrades), symbol: "chart.line.uptrend.xyaxis")
        case .requirements: Crumb(title: String(localized: .rootNavRequirements), symbol: "flag")
        case .people: Crumb(title: String(localized: .rootNavPeople), symbol: "person")
        case .codes: Crumb(title: String(localized: .rootNavCodes), symbol: "number")
        case .settings: Crumb(title: String(localized: .rootNavSettings), symbol: "gearshape")
        case .whatsNew: Crumb(title: String(localized: .whatsNewTitle), symbol: "sparkles")
        case .proposals: Crumb(title: String(localized: .rootNavProposals), symbol: "tray")
        case .missing: Crumb(title: entry.link.string, symbol: "questionmark.folder")
        case .today: Crumb(title: String(localized: .rootNavToday), symbol: "house")
        }
    }

    func tabTitle(of entry: Navigator.Entry) -> String? {
        switch entry.link.kind {
        case .today: nil
        case .session, .unit, .note, .material, .assignment, .exam, .problemSet, .person, .recording:
            itemName(of: entry) ?? placeCrumb(of: entry).title
        case .grades, .requirements, .people, .codes, .settings, .whatsNew, .proposals, .semester, .course, .card:
            placeCrumb(of: entry).title
        }
    }
}
