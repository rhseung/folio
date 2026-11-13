import FolioDomain
import SwiftUI

/// One window's tabs, each a layout of panes with their own histories (`TabPanes`, #62). The window draws them in its
/// toolbar row itself rather than as AppKit window tabs, whose bar took a row of its own over the frame.
///
/// The screens of the most recent tabs stay alive behind the one in front (`alive`, chosen by `TabKeep`), so going back
/// to one finds it as it was left; the others are drawn again from their address.
@MainActor @Observable
final class WindowTabs {
    private(set) var strip: TabStrip<UUID> {
        didSet {
            if oldValue.selected != strip.selected { left[oldValue.selected] = now() }
            settle()
        }
    }
    private var tabs: [UUID: TabPanes]
    /// The tabs whose screens are alive, the one in front among them.
    private(set) var alive: Set<UUID>
    /// When each tab last went behind another.
    @ObservationIgnored private var left: [UUID: Date] = [:]
    /// The tabs playing a recording. `TabKeep` keeps them alive: dropping the screen would stop the audio.
    private(set) var playing: Set<UUID> = []
    /// The panes playing, which the strip marks, each with how to pause it.
    private(set) var playingPanes: Set<UUID> = []
    @ObservationIgnored private var pauses: [UUID: @MainActor () -> Void] = [:]
    /// Closing the last tab closes the window, which the window hands over once it has one.
    @ObservationIgnored var closeWindow: @MainActor () -> Void = {}
    @ObservationIgnored var now: @MainActor () -> Date = { .now }
    @ObservationIgnored var policy = WindowTabs.keep
    /// Where the panes of the tab in front are across the window, for a tab dragged onto their edge (`TabBar`). Not
    /// watched: it changes with every frame of a resize, and only a drag reads it.
    @ObservationIgnored var contentFrame: CGRect = .zero
    /// Where a dragged tab would join the tab in front if let go now, which the panes mark.
    var drop: MergeDrop?

    enum MergeEdge: Equatable {
        case leading, trailing
    }

    struct MergeDrop: Equatable {
        var edge: MergeEdge
        /// Of the row, what the joining panes would take (`PaneLayout.merge`).
        var share: Double
    }

    /// How many screens wait behind the front tab and for how long. A note tab costs most: its preview's page runs in a
    /// WebKit process of its own, about 80MB for a usual note and 270MB for a long one with math and diagrams, against
    /// 10MB for a course page (measured with `TabMemoryProbe`; the numbers are in #304).
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
    /// The focused pane's history in the tab in front.
    var current: Navigator { tabs[strip.selected]?.focused ?? Navigator() }
    var front: TabPanes? { tabs[strip.selected] }

    func panes(_ id: UUID) -> TabPanes? { tabs[id] }
    /// The focused pane's history in a tab.
    func navigator(_ id: UUID) -> Navigator? { tabs[id]?.focused }
    /// The focused pane's breadcrumb steps, which its screen sets while alive. With one trail for the window, a screen
    /// kept behind would keep its steps in the front tab's trail.
    func trail(_ id: UUID) -> CrumbTrail? { tabs[id]?.focusedTrail }
    /// The tab a pane's history is in.
    func panes(holding navigator: Navigator) -> TabPanes? { tabs.values.first { $0.index(of: navigator) != nil } }

    /// `fromLink`: beside the tab in front rather than last.
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

    /// A pane's screen saying it plays (with how to pause it) or has stopped (nil); without a pane, the tab's first.
    func play(_ id: UUID, pane: UUID? = nil, pause: (@MainActor () -> Void)?) {
        if let pane = pane ?? tabs[id]?.ids.first {
            pauses[pane] = pause
            let on = pause != nil && strip.tabs.contains(id)
            if on != playingPanes.contains(pane) { if on { playingPanes.insert(pane) } else { playingPanes.remove(pane) } }
        }
        settlePlaying()
    }

    /// From the tabs still open: a closed tab's screen says it stopped only once the tab is gone.
    private func settlePlaying() {
        let open = Set(strip.tabs.flatMap { tabs[$0]?.ids ?? [] })
        let panes = playingPanes.intersection(open)
        if panes != playingPanes { playingPanes = panes }
        let tabs = Set(strip.tabs.filter { self.tabs[$0]?.ids.contains(where: panes.contains) == true })
        if tabs != playing { playing = tabs }
    }

    /// Every pane of the tab that plays.
    func pause(_ id: UUID) {
        for pane in tabs[id]?.ids ?? [] where playingPanes.contains(pane) { pauses[pane]?() }
    }

    func pause(pane: UUID) { pauses[pane]?() }

    func closeOthers(than id: UUID) {
        strip.closeOthers(than: id)
        tabs = tabs.filter { $0.key == id }
    }

    /// Whether tab `id` can join `target` ("옆 칸으로 합치기"): any other tab, however many panes either has.
    func canMerge(_ id: UUID, into target: UUID) -> Bool {
        id != target && tabs[id] != nil && tabs[target] != nil
    }

    /// "옆 칸으로 합치기" (2026-11-09 사용자): tab `id`'s panes join `target`'s, with their histories, at `edge` (nil:
    /// right of its focused pane, as "옆 칸에 열기" opens one), and tab `id` closes. `target` comes to the front.
    func merge(_ id: UUID, into target: UUID, at edge: MergeEdge? = nil) {
        guard canMerge(id, into: target), let source = tabs[id], let into = tabs[target] else { return }
        let index = switch edge {
        case .leading: 0
        case .trailing: into.count
        case nil: into.focus + 1
        }
        guard into.merge(source, at: index), strip.close(id) else { return }
        tabs[id] = nil
        strip.select(target)
        // Its panes took new IDs here, and their screens are drawn anew: the old IDs' marks go.
        settlePlaying()
    }

    /// Where tab `id`, dragged to `point` across the window, would join the tab in front: within `mergeZone` of the
    /// panes' leading or trailing edge, below their top. Nil for the tab in front itself.
    func drop(for id: UUID, at point: CGPoint) -> MergeDrop? {
        let frame = contentFrame
        guard id != selected, canMerge(id, into: selected), let source = tabs[id], let front = front, frame.width > 0,
              frame.minY <= point.y, point.y <= frame.maxY else { return nil }
        let zone = min(Self.mergeZone, frame.width / 3)
        let edge: MergeEdge
        if point.x <= frame.minX + zone { edge = .leading } else if point.x >= frame.maxX - zone { edge = .trailing } else { return nil }
        return MergeDrop(edge: edge, share: Double(source.count) / Double(source.count + front.count))
    }

    /// How far in from the panes' edge a dragged tab joins them: wide enough to find without aiming, narrow enough to
    /// leave the middle for letting go without joining.
    static let mergeZone = Theme.Size.paneMin / 2

    /// Takes a tab out for a window of its own; nil for the last one, which is the window already.
    func take(_ id: UUID) -> TabPanes? {
        guard count > 1, let panes = tabs[id], strip.close(id) else { return nil }
        tabs[id] = nil
        return panes
    }

    /// Lets go of the screens that have waited behind too long; the window calls it as the minutes pass.
    func tick() { settle() }

    /// The system is short of memory: only the tab in front keeps its screen.
    func dropBackground() { settle(pressure: true) }

    private func settle(pressure: Bool = false) {
        left = left.filter { strip.tabs.contains($0.key) }
        let kept = TabKeep.alive(selected: strip.selected, alive: alive.intersection(strip.tabs), left: left, now: now(), policy: policy,
                                 pressure: pressure, playing: playing)
        if kept != alive { alive = kept }
    }
}

/// The screens of the tabs kept alive, stacked. Only the one in front shows and takes the pointer and the keys: a kept
/// screen's ⌘S or ⌘E, or the zoom keys of a file it shows, would otherwise act on a page no one sees. Each pane's
/// screen keeps its own breadcrumb steps and moves its own pane when it opens a link.
struct TabScreens: View {
    let tabs: WindowTabs
    let workspace: Workspace
    /// For the pane whose history this is.
    let openLink: (Navigator) -> OpenLinkAction
    @State private var sizes = ScreenSizes()
    #if os(iOS)
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var multipleWindows
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    /// "새 탭으로 옮기기" from a pane's menu: a tab of its own, its history with it. The iPhone's frame has no tab
    /// strip, so there it goes to a window of its own, and nowhere where the system allows only one; a tab there would
    /// be one with no bar to find it by.
    var newTab: ((Navigator, ColumnPrefs) -> Void)? {
        let here: (Navigator, ColumnPrefs) -> Void = { [tabs] navigator, columns in tabs.open(navigator, columns: columns, fromLink: true) }
        #if os(macOS)
        return here
        #else
        if sizeClass == .regular { return here }
        guard multipleWindows else { return nil }
        return { [openWindow] navigator, columns in
            var request = WindowRequest(link: navigator.current.link, course: navigator.current.course, history: navigator.history)
            request.columns = [columns.names]
            openWindow(id: FolioApp.mainWindow, value: request)
        }
        #endif
    }

    var body: some View {
        ZStack {
            // In the strip's order, so a screen keeps its place in the stack, and its state, as others come and go.
            ForEach(tabs.ids.filter { tabs.alive.contains($0) }, id: \.self) { id in
                if let panes = tabs.panes(id) {
                    let front = id == tabs.selected
                    // A screen behind keeps the size it last had in front, so resizing the window lays out only the
                    // one in front: a note's text and preview page reflowing out of sight made each frame of a live
                    // resize wait on every kept tab. It takes the window's size again when it comes back.
                    let kept = front ? nil : sizes[id]
                    PaneRow(workspace: workspace, panes: panes, front: front, openLink: openLink,
                            play: { [tabs] pane, pause in tabs.play(id, pane: pane, pause: pause) },
                            newTab: newTab)
                        .onGeometryChange(for: CGSize.self, of: \.size) { sizes[id] = $0 }
                        .frame(width: kept?.width, height: kept?.height, alignment: .topLeading)
                        // The window's size whatever the screen inside: with no least size given, a screen behind
                        // sized the stack to itself and pushed the one in front past the window's edge.
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity,
                               alignment: kept == nil ? .center : .topLeading)
                        .opacity(front ? 1 : 0)
                        .allowsHitTesting(front)
                        .disabled(!front)
                        .accessibilityHidden(!front)
                        .zIndex(front ? 1 : 0)
                }
            }
        }
        .onChange(of: tabs.alive) { _, alive in sizes.keep(alive) }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { tabs.contentFrame = $0 }
        .overlay { MergeMark(tabs: tabs) }
    }
}

/// Where a tab dragged onto the panes' edge would join them: the room its panes would take, in the accent, as the
/// focused pane's ring is. Only the iPad lacks it, having no tabs to drag.
private struct MergeMark: View {
    let tabs: WindowTabs

    var body: some View {
        let drop = tabs.drop
        GeometryReader { proxy in
            if let drop {
                let shape = RoundedRectangle(cornerRadius: Theme.Radius.floating)
                shape.fill(Theme.Palette.chromeSelected.opacity(Theme.Opacity.tint))
                    .overlay { shape.strokeBorder(Theme.Palette.chromeSelected, lineWidth: 1) }
                    .frame(width: proxy.size.width * drop.share)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: drop.edge == .leading ? .leading : .trailing)
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(.snappy(duration: 0.2), value: drop)
    }
}

extension EnvironmentValues {
    /// Where a screen says it is playing a recording, so its tab is kept and its pane marked behind the front one.
    @Entry var tabPlaying: @MainActor ((@MainActor () -> Void)?) -> Void = { _ in }
}

/// The tabs at each width they can take, as `TabBar` measures them. Not observed: nothing draws from them, they only
/// feed `ToolbarRow`.
@MainActor final class TabSizes {
    /// The tab in front's trail alone, then its whole capsule with its other segments named and as icons.
    var trail: CGFloat = 0
    var front: CGFloat = 0
    var compactFront: CGFloat = 0
    var more: CGFloat = 0
    private var others: [UUID: [TabForm: CGFloat]] = [:]

    var frontFit: TabFit.Front {
        TabFit.Front(trail: Double(trail), chrome: Double(front - trail), compactChrome: Double(compactFront - trail))
    }

    func set(_ width: CGFloat, _ id: UUID, _ form: TabForm) { others[id, default: [:]][form] = width }

    /// Until measured, an icon.
    func other(_ id: UUID) -> TabFit.Other {
        let widths = others[id] ?? [:]
        let icon = TabBar.icon
        return TabFit.Other(full: Double(widths[.full] ?? icon), icons: Double(widths[.icons] ?? icon), stacked: Double(widths[.stacked] ?? icon))
    }

    func keep(_ ids: Set<UUID>) { others = others.filter { ids.contains($0.key) } }
}

/// The size each kept screen was last laid out at. Not observed: it changes every frame of a resize, which would redraw
/// the stack each frame; it is read only when a screen goes behind.
@MainActor final class ScreenSizes {
    private var sizes: [UUID: CGSize] = [:]

    subscript(id: UUID) -> CGSize? {
        get { sizes[id] }
        set { sizes[id] = newValue }
    }

    func keep(_ ids: Set<UUID>) { sizes = sizes.filter { ids.contains($0.key) } }
}

/// The system running short of memory, one notification on the Mac and the iPad alike.
enum MemoryPressure {
    #if os(macOS)
    static let warning = Notification.Name("FolioMemoryPressure")
    @MainActor private static var source: DispatchSourceMemoryPressure?

    /// Once, for the app's life: the Mac has no memory warning of its own to listen to.
    @MainActor static func start() {
        guard source == nil else { return }
        let pressure = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        pressure.setEventHandler { NotificationCenter.default.post(name: warning, object: nil) }
        pressure.resume()
        source = pressure
    }

    static var publisher: NotificationCenter.Publisher { NotificationCenter.default.publisher(for: warning) }
    #else
    static func start() {}
    static var publisher: NotificationCenter.Publisher {
        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
    }
    #endif
}

extension FocusedValues {
    /// The key window's tabs, for the menu bar's tab commands.
    @Entry var windowTabs: WindowTabs?
    /// The key window's tab in front, for 보기 › 칸 폭 맞추기.
    @Entry var frontPanes: TabPanes?
}

extension Workspace {
    /// The screen a step is on with the sidebar's icon and name for it: the head of the window's breadcrumb, and the
    /// mark on a tab.
    func placeCrumb(of entry: Navigator.Entry) -> Crumb {
        switch Screen(entry) {
        case .course(let id): Crumb(title: course(id)?.title ?? "", symbol: course(id)?.file.course.icon, dot: accent(id).color)
        case .semester(let id):
            { let semester = transcript.semesters.first { $0.id == id }
              return Crumb(title: semester?.title ?? "", symbol: semester?.term == .credited ? "checkmark.seal" : "folder") }()
        case .grades: Crumb(title: String(localized: .rootNavGrades), symbol: "chart.line.uptrend.xyaxis")
        case .requirements: Crumb(title: String(localized: .rootNavRequirements), symbol: "flag")
        case .people: Crumb(title: String(localized: .rootNavPeople), symbol: "person")
        case .codes: Crumb(title: String(localized: .rootNavCodes), symbol: "number")
        case .settings: Crumb(title: String(localized: .rootNavSettings), symbol: "gearshape")
        case .whatsNew: Crumb(title: String(localized: .whatsNewTitle), symbol: "sparkles")
        // The address itself, as the page says it can't be found: not today's, which the page no longer shows.
        case .missing: Crumb(title: entry.link.string, symbol: "questionmark.folder")
        case .today: Crumb(title: String(localized: .rootNavToday), symbol: "house")
        }
    }

    /// The name on a tab behind the one in front: the session, note, file or person it shows, else its screen's name.
    /// A course's section alone ("노트") says less than the course. Nil for Today, whose house says it.
    func tabTitle(of entry: Navigator.Entry) -> String? {
        switch entry.link.kind {
        case .today: nil
        case .session, .unit, .note, .material, .assignment, .exam, .problemSet, .person, .recording: itemName(of: entry) ?? placeCrumb(of: entry).title
        // A card names only its page ("카드"), which says less than the course.
        case .grades, .requirements, .people, .codes, .settings, .whatsNew, .semester, .course, .card: placeCrumb(of: entry).title
        }
    }
}

/// The window's tabs in its toolbar row: the tab in front is the breadcrumb of where its focused pane is, with a close
/// button; a tab of several panes is one capsule with a segment for each (B2 in #62). The others are their icons and a
/// short name, then icons alone, then a menu, as the row runs out (`TabFit`). A + at the end opens Today in a new tab.
struct TabBar: View {
    let tabs: WindowTabs
    let workspace: Workspace
    /// The focused pane's whole trail: its screen, then what the screen added.
    let crumbs: [Crumb]
    /// Where the row has room for the tabs, worked out there as the window resizes.
    let toolbar: ToolbarRow
    let moveToWindow: (UUID) -> Void
    /// "지금 배치 저장…": asks for the name the tab's panes are saved under.
    var nameLayout: (TabPanes) -> Void = { _ in }
    /// "배치 관리…": the settings where the user's layouts are named, ordered and deleted.
    var manageLayouts: () -> Void = {}
    @State private var sizes = TabSizes()
    @State private var frames: [UUID: CGRect] = [:]
    @State private var dragged: (id: UUID, start: CGFloat)?
    @State private var dragOffset: CGFloat = 0
    /// The strip's origin across the window, which a drag's points are measured from: the panes' edge it may be
    /// dragged onto is measured across the window too.
    @State private var stripOrigin: CGPoint = .zero
    /// Back to false however a tab's drag ends: one the system cuts short has no end to clear the merge mark.
    @GestureState private var dragging = false

    static let gap = Theme.Space.s
    static let icon = Theme.Size.toolbarButton
    static let plus = "plus"
    /// The new-tab glyph's ink, which sets it one gap after the last capsule (`TabFit.newTabSpacing`). Not its image's
    /// width: that has the symbol's side bearings in it, 2 points a side, and the + still sat further off than the
    /// capsules from each other.
    static let plusInk = inkWidth(of: plus, size: Theme.Glyph.toolbarSize)

    static func inkWidth(of symbol: String, size: CGFloat) -> CGFloat {
        #if os(iOS)
        // The symbol drawn into a bitmap of its own and the inked columns counted, as on the Mac.
        guard let image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: .regular)),
              let cg = image.cgImage else { return size }
        let width = cg.width, height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return size }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        let inked = (0..<width).filter { x in (0..<height).contains { pixels[($0 * width + x) * 4 + 3] > 127 } }
        guard let first = inked.first, let last = inked.last else { return size }
        return CGFloat(last + 1 - first) / image.scale
        #else
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: .regular)) else { return size }
        let scale = 4
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(image.size.width) * scale,
                                         pixelsHigh: Int(image.size.height) * scale, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return size }
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        let inked = (0..<rep.pixelsWide).filter { x in
            (0..<rep.pixelsHigh).contains { (rep.colorAt(x: x, y: $0)?.alphaComponent ?? 0) > 0.5 }
        }
        guard let first = inked.first, let last = inked.last else { return size }
        return CGFloat(last + 1 - first) / CGFloat(scale)
        #endif
    }

    var body: some View {
        let others = tabs.ids.filter { $0 != tabs.selected }
        // Changes only as the fit or the front tab's trail does, not with every width the window passes through: a
        // redraw of the tabs on every frame of a live resize is work the frame can't spare (in the AppKit toolbar,
        // which rebuilt its items' menu form each time, it held the window to a few frames a second).
        let placement = toolbar.placement
        let fit = placement.fit
        let shown = Array(others.prefix(fit.shown))
        let hidden = Array(others.dropFirst(fit.shown))
        let row = tabs.ids.filter { $0 == tabs.selected || shown.contains($0) }
        HStack(spacing: Self.gap) {
            ForEach(row, id: \.self) { id in
                Group {
                    if id == tabs.selected {
                        // Its own width while it fits: offered the row, the trail's frame would take all of it, and
                        // held to its measured width a fraction short, it cut the course's name.
                        if let trail = placement.trail {
                            front(crumbRoom: trail, compact: fit.compactFront)
                                .frame(width: trail + CGFloat(toolbar.measures.front.chrome(compact: fit.compactFront)))
                        } else {
                            front(crumbRoom: .infinity, compact: fit.compactFront).fixedSize()
                        }
                    } else {
                        // At their measured width: `TabFit` already made room, and squeezed they'd cut their names.
                        tab(id, form: TabForm(fit)).fixedSize()
                    }
                }
                #if os(macOS) && (DEBUG || RESIZE_PROBE)
                .background { if id == row.first { ResizeMarker(name: "firstTab") } }
                #endif
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { frames[id] = $0 }
                #if DEBUG && os(macOS)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { if id == tabs.selected { LayoutSnapshots.selectedTab = $0 } }
                #endif
                .offset(x: dragged?.id == id ? dragOffset : 0)
                .zIndex(dragged?.id == id ? 1 : 0)
                .simultaneousGesture(drag(id, row: row))
                .contextMenu { menu(id) }
            }
            if !hidden.isEmpty { more(hidden) }
            Button(.tabsNew, systemImage: Self.plus) { tabs.open() }
                .labelStyle(.iconOnly)
                .buttonStyle(.toolbar)
                .help(Text(.tabsNewHelp))
                .padding(.leading, placement.newTabSpacing - Self.gap)
                #if os(macOS) && (DEBUG || RESIZE_PROBE)
                .background { ResizeMarker(name: "newTab") }
                #endif
        }
        .coordinateSpace(.named(Self.space))
        .onGeometryChange(for: CGPoint.self) { $0.frame(in: .global).origin } action: { stripOrigin = $0 }
        .onChange(of: dragging) { _, now in if !now { tabs.drop = nil } }
        .background { measures(others) }
        .onChange(of: tabs.selected) { report() }
        .onChange(of: tabs.ids) { _, ids in
            let open = Set(ids)
            sizes.keep(open)
            report()
            frames = frames.filter { open.contains($0.key) }
        }
        .animation(.snappy(duration: 0.25), value: tabs.ids)
        // A new fit (names to icons, into the menu) comes at once, not animated: it comes mid-resize, and animated the
        // strip slid in from the width it had, the first tab off the panel's edge by as much for a quarter second.
        // Never wider than the row leaves it: wider, the strip runs under the search field and the buttons.
        .frame(width: placement.width, alignment: .leading)
        .padding(.leading, placement.lead)
    }

    static let space = "tabs"

    /// Tells the row what the tabs take, straight from the measures: state set in a measure's callback reached the
    /// body late or not at all, and the row held the front tab to a width it had long outgrown, running the strip
    /// over the search field.
    func report() {
        let others = tabs.ids.filter { $0 != tabs.selected }
        let measures = ToolbarRow.Measures(front: sizes.frontFit, others: others.map(sizes.other), more: sizes.more)
        if measures != toolbar.measures { toolbar.measures = measures }
    }

    static let closeSize = Theme.Size.tile

    @ViewBuilder func front(crumbRoom: CGFloat, compact: Bool) -> some View {
        if let panes = tabs.front, panes.count > 1 {
            joined(panes, crumbRoom: crumbRoom, compact: compact)
        } else {
            HStack(spacing: Theme.Space.xs) {
                Breadcrumb(crumbs: crumbs, foldWidth: crumbRoom, maxWidth: crumbRoom)
                // Not on a lone tab: there it would close the window, which the window's own button already does.
                if tabs.count > 1 { closeButton(tabs.selected) }
            }
            .padding(.leading, Theme.Space.m)
            .padding(.trailing, tabs.count > 1 ? Theme.Space.xs : Theme.Space.m)
            .frame(height: Theme.Size.toolbarButton)
            .tabSurface(front: true)
        }
    }

    /// The tab in front with several panes: a segment for each, the focused one the breadcrumb in full ink, the others
    /// a gray icon and a dimmed short name (icons alone at `compact`); the close button at the end closes the tab.
    func joined(_ panes: TabPanes, crumbRoom: CGFloat, compact: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Segment.all(panes, workspace: workspace, playing: tabs.playingPanes)) { segment in
                if segment.index > 0 { SegmentRule() }
                TabSegment(mark: segment.mark, crumbs: segment.index == panes.focus ? crumbs : nil, crumbRoom: crumbRoom, iconOnly: compact,
                           playing: segment.playing,
                           select: { panes.press(pane: segment.id) }, close: { panes.close(pane: segment.id) },
                           pause: { [tabs] in tabs.pause(pane: segment.id) })
                    .contextMenu {
                        if let i = panes.ids.firstIndex(of: segment.id) {
                            PaneMenu(panes: panes, index: i) { [tabs] navigator, columns in tabs.open(navigator, columns: columns, fromLink: true) }
                        }
                        // A segment's menu stands in for the tab's, so a tab of panes, the one a layout is saved from,
                        // has "배치 ▸" too.
                        Divider()
                        LayoutMenu(choices: workspace.layoutChoices(for: panes, save: { nameLayout(panes) }, manage: manageLayouts))
                    }
            }
            if tabs.count > 1 { closeButton(tabs.selected).padding(.leading, Theme.Space.xxs) }
        }
        .padding(.horizontal, Theme.Space.xs)
        .frame(height: Theme.Size.toolbarButton)
        .tabSurface(front: true)
    }

    /// One pane as the tab bar draws it, read from the panes before `ForEach` gets it. Not its place to read them by
    /// inside: as a pane closed, SwiftUI ran the segment it had once more with the place it had then, past the end of
    /// the panes, and the app crashed (2026-11-08).
    struct Segment: Identifiable {
        let id: UUID
        let index: Int
        let mark: Crumb
        let playing: Bool

        @MainActor static func all(_ panes: TabPanes, workspace: Workspace, playing: Set<UUID>) -> [Segment] {
            panes.ids.indices.map { i in
                Segment(id: panes.ids[i], index: i, mark: workspace.paneMark(of: panes.navigators[i].current, trail: panes.trails[i]),
                        playing: playing.contains(panes.ids[i]))
            }
        }
    }

    func closeButton(_ id: UUID) -> some View {
        Button { tabs.close(id) } label: {
            Image(systemName: "xmark").font(Theme.Glyph.small)
                .frame(width: Self.closeSize, height: Self.closeSize)
                .contentShape(.circle)
        }
        .buttonStyle(.pointing(.plain))
        .foregroundStyle(Theme.Palette.chromeText)
        .help(Text(.tabsCloseHelp))
        .accessibilityLabel(Text(.tabsClose))
    }

    @ViewBuilder func tab(_ id: UUID, form: TabForm) -> some View {
        let entry = tabs.navigator(id)?.current ?? Navigator.Entry(link: .place(.today))
        let title = workspace.tabTitle(of: entry)
        let name = tabs.panes(id).flatMap(workspace.presetName(of:)) ?? title ?? workspace.placeCrumb(of: entry).title
        if let panes = tabs.panes(id), panes.count > 1 {
            // Not one button: the playing pane's speaker is a button of its own, and inside the tab's label it would
            // select the tab.
            label(id, form: form)
                .help(name)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(name)
        } else {
            let playing = tabs.playing.contains(id)
            Button { tabs.select(id) } label: {
                label(entry, title: form == .full ? title : nil, playing: playing)
            }
            .buttonStyle(.pointing(.plain))
            // Its own button over the room the label leaves it: a button inside the tab's label would select the tab.
            .overlay(alignment: .trailing) { if playing && form == .full { speaker(id) } }
            .help(name)
            .accessibilityLabel(name)
        }
    }

    /// A tab behind the front one. One pane: its icon, and its name unless it has none or the row is short. Several:
    /// their icons joined, with the preset's name the layout is, or the first icon and "+n" (`TabFit`'s step 2). The
    /// playing pane's icon is a speaker that pauses it; stacked into one icon, the tab shows the speaker there and
    /// selects, as a tab of one pane does at an icon.
    @ViewBuilder func label(_ id: UUID, form: TabForm) -> some View {
        if let panes = tabs.panes(id), panes.count > 1 {
            let segments = Segment.all(panes, workspace: workspace, playing: tabs.playingPanes)
            HStack(spacing: 0) {
                if form == .stacked {
                    Button { tabs.select(id) } label: {
                        HStack(spacing: Theme.Space.xxs) {
                            if segments.contains(where: \.playing) { speakerIcon } else if let first = segments.first { PlaceIcon(place: first.mark) }
                            Text(.panesMoreCount(segments.count - 1)).font(Theme.Typeface.caption).monospacedDigit()
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.pointing(.plain))
                } else {
                    ForEach(segments) { segment in
                        if segment.index > 0 { SegmentRule() }
                        Group {
                            if segment.playing {
                                Button { tabs.pause(pane: segment.id) } label: { speakerIcon.contentShape(.rect) }
                                    .help(Text(.tabsPause))
                                    .accessibilityLabel(Text(.tabsPause))
                            } else {
                                Button { tabs.select(id) } label: { PlaceIcon(place: segment.mark).contentShape(.rect) }
                                    .accessibilityLabel(segment.mark.title)
                            }
                        }
                        .buttonStyle(.pointing(.plain))
                        .padding(.horizontal, Theme.Space.xs)
                    }
                    if form == .full, let preset = workspace.presetName(of: panes) {
                        Button { tabs.select(id) } label: { CappedWidth(width: Theme.Size.tabName) { Text(preset).lineLimit(1) } }
                            .buttonStyle(.pointing(.plain))
                            .padding(.leading, Theme.Space.xxs)
                            .padding(.trailing, Theme.Space.xs)
                    }
                }
            }
            .padding(.horizontal, Theme.Space.xs)
            .font(Theme.Typeface.body)
            .foregroundStyle(Theme.Palette.chromeText)
            .frame(height: Theme.Size.toolbarButton)
            .tabSurface(front: false)
            .contentShape(.capsule)
            // The room between the icons selects the tab too; the buttons in it take their own presses first.
            .onTapGesture { tabs.select(id) }
        } else {
            let entry = tabs.navigator(id)?.current ?? Navigator.Entry(link: .place(.today))
            label(entry, title: form == .full ? workspace.tabTitle(of: entry) : nil, playing: tabs.playing.contains(id))
        }
    }

    /// A tab of one pane behind the front one: its icon, and its name unless it has none or the row is short. Playing
    /// a recording, it leaves room at its end for the speaker, set as the front tab sets its close button, or shows the
    /// speaker in place of its icon when the row is short.
    @ViewBuilder func label(_ entry: Navigator.Entry, title: String?, playing: Bool = false) -> some View {
        let place = workspace.placeCrumb(of: entry)
        Group {
            if let title {
                HStack(spacing: Theme.Space.tight) {
                    PlaceIcon(place: place)
                    CappedWidth(width: Theme.Size.tabName) { Text(title).lineLimit(1) }
                }
                .padding(.leading, Theme.Space.s)
                .padding(.trailing, playing ? Theme.Space.xs + Self.closeSize + Theme.Space.xs : Theme.Space.m)
            } else if playing {
                speakerIcon.frame(width: Self.icon)
            } else {
                PlaceIcon(place: place).frame(width: Self.icon)
            }
        }
        .font(Theme.Typeface.body)
        .foregroundStyle(Theme.Palette.chromeText)
        .frame(height: Theme.Size.toolbarButton)
        .tabSurface(front: false)
        .contentShape(.capsule)
    }

    static let speakerSymbol = "speaker.wave.2.fill"

    var speakerIcon: some View { LineIcon(symbol: Self.speakerSymbol).foregroundStyle(Theme.Palette.chromeIcon) }

    func speaker(_ id: UUID) -> some View {
        Button { tabs.pause(id) } label: {
            Image(systemName: Self.speakerSymbol).font(Theme.Glyph.small)
                .frame(width: Self.closeSize, height: Self.closeSize)
                .contentShape(.circle)
        }
        .buttonStyle(.pointing(.plain))
        .foregroundStyle(Theme.Palette.chromeText)
        .padding(.trailing, Theme.Space.xs)
        .help(Text(.tabsPause))
        .accessibilityLabel(Text(.tabsPause))
    }

    /// A tab as a menu names it: the preset its panes are, else what its focused pane shows; with that pane's icon, or
    /// the speaker while it plays.
    func menuItem(_ id: UUID) -> (name: String, symbol: String) {
        let entry = tabs.navigator(id)?.current ?? Navigator.Entry(link: .place(.today))
        let place = workspace.placeCrumb(of: entry)
        let name = tabs.panes(id).flatMap(workspace.presetName(of:)) ?? workspace.tabTitle(of: entry) ?? place.title
        return (name, tabs.playing.contains(id) ? Self.speakerSymbol : place.symbol ?? CourseMark.defaultIcon)
    }

    func more(_ hidden: [UUID]) -> some View {
        Menu {
            ForEach(hidden, id: \.self) { id in
                let item = menuItem(id)
                Button(item.name, systemImage: item.symbol) { tabs.select(id) }
            }
        } label: {
            moreLabel(hidden.count)
        }
        .menuStyle(.button)
        // Plain, not `.pointing(.plain)`: a custom style turns the menu back into a pop-up button, whose own margins
        // drew the capsule wider than measured and set it further from its neighbors than they are from each other.
        .buttonStyle(.plain)
        .pointingHand()
        .menuIndicator(.hidden)
        .fixedSize()
        .help(Text(.tabsMore(hidden.count)))
        .accessibilityLabel(Text(.tabsMore(hidden.count)))
    }

    /// "+n" alone: the room it leaves goes to the tabs. Its hover and VoiceOver say what it holds.
    func moreLabel(_ n: Int) -> some View {
        Text(.tabsMoreCount(n))
            .monospacedDigit()
            .font(Theme.Typeface.body)
            .foregroundStyle(Theme.Palette.chromeText)
            .toolbarField()
    }

    func menu(_ id: UUID) -> some View {
        Group {
            if tabs.playing.contains(id) { Button(.tabsPause) { tabs.pause(id) }; Divider() }
            Button(.tabsClose) { tabs.close(id) }
            Button(.tabsCloseOthers) { tabs.closeOthers(than: id) }.disabled(tabs.count < 2)
            Divider()
            mergeMenu(into: id)
            Button(.tabsMoveToWindow) { moveToWindow(id) }.disabled(tabs.count < 2)
            if let panes = tabs.panes(id) {
                Divider()
                LayoutMenu(choices: workspace.layoutChoices(for: panes, save: { nameLayout(panes) }, manage: manageLayouts))
            }
        }
    }

    /// "옆 칸으로 합치기 ▸": every other tab, whose panes join this one's right of its focused pane. The menu's way to
    /// what dragging a tab onto the panes' edge does.
    func mergeMenu(into id: UUID) -> some View {
        let others = tabs.ids.filter { $0 != id }
        return Menu(String(localized: .tabsMerge)) {
            ForEach(others, id: \.self) { other in
                let item = menuItem(other)
                Button(item.name, systemImage: item.symbol) { tabs.merge(other, into: id) }
            }
        }
        .disabled(others.isEmpty)
    }

    /// What every tab would take at each width it can have, drawn once out of sight: a tab drawn as an icon can't tell
    /// how wide its name would make it.
    func measures(_ others: [UUID]) -> some View {
        ZStack {
            Breadcrumb(crumbs: crumbs, foldWidth: .infinity, maxWidth: .infinity).fixedSize()
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { sizes.trail = $0; report() }
            front(crumbRoom: .infinity, compact: false).fixedSize()
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { sizes.front = $0; report() }
            front(crumbRoom: .infinity, compact: true).fixedSize()
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { sizes.compactFront = $0; report() }
            ForEach(others, id: \.self) { id in
                ForEach(TabForm.allCases, id: \.self) { form in
                    label(id, form: form).fixedSize()
                        .onGeometryChange(for: CGFloat.self, of: \.size.width) { sizes.set($0, id, form); report() }
                }
            }
            // Two digits: the menu's width hardly changes with its count.
            moreLabel(max(others.count, 10)).fixedSize()
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { sizes.more = $0; report() }
        }
        .hidden()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Drags a tab along the row; passing a neighbor's middle swaps them, as in Safari. Down onto the leading or
    /// trailing edge of the panes, it joins the tab in front there when let go ("옆 칸으로 합치기", 2026-11-09 사용자),
    /// the room it would take marked meanwhile (`MergeMark`). Out of the window is #305's.
    func drag(_ id: UUID, row: [UUID]) -> some Gesture {
        DragGesture(minimumDistance: Theme.Space.xs, coordinateSpace: .named(Self.space))
            .updating($dragging) { _, state, _ in state = true }
            .onChanged { value in
                guard let frame = frames[id] else { return }
                if dragged?.id != id { dragged = (id, frame.minX) }
                let point = across(value.location)
                let drop = tabs.drop(for: id, at: point)
                if drop != tabs.drop { tabs.drop = drop }
                // Over the panes the tab is on its way to join them, not to another place in the row.
                let content = tabs.contentFrame
                if content.isEmpty || point.y < content.minY { reorder(id, row: row, to: value.location.x) }
                // The tab follows the pointer from where it was picked up, whatever place the row now gives it.
                dragOffset = value.translation.width - ((frames[id]?.minX ?? frame.minX) - (dragged?.start ?? frame.minX))
            }
            .onEnded { value in
                // From where it was let go rather than the mark, which `dragging` may have cleared already.
                let drop = tabs.drop(for: id, at: across(value.location))
                tabs.drop = nil
                if let drop { tabs.merge(id, into: tabs.selected, at: drop.edge) }
                withAnimation(.snappy(duration: 0.2)) {
                    dragged = nil
                    dragOffset = 0
                }
            }
    }

    func across(_ location: CGPoint) -> CGPoint { CGPoint(x: stripOrigin.x + location.x, y: stripOrigin.y + location.y) }

    func reorder(_ id: UUID, row: [UUID], to x: CGFloat) {
        let others = row.filter { $0 != id }
        let before = others.filter { (frames[$0]?.midX ?? 0) < x }.count
        var rest = tabs.ids.filter { $0 != id }
        let index: Int = if before < others.count { rest.firstIndex(of: others[before]) ?? 0 }
            else { others.last.flatMap { rest.firstIndex(of: $0) }.map { $0 + 1 } ?? rest.count }
        rest.insert(id, at: index)
        if rest != tabs.ids { tabs.move(id, to: index) }
    }
}

/// How a tab behind the front one is drawn, by `TabFit`'s steps.
enum TabForm: CaseIterable {
    case full, icons, stacked

    init(_ fit: TabFit.Layout) {
        self = !fit.iconsOnly ? .full : fit.stacked ? .stacked : .icons
    }
}

/// One pane's segment of the tab in front. The focused one is raised in paper and holds the breadcrumb; the others
/// are an icon and a short name and focus their pane when pressed. Under the pointer, a small × closes the pane; its
/// place is kept when hidden, so the tab doesn't change width as the pointer passes.
private struct TabSegment: View {
    let mark: Crumb
    /// The breadcrumb, on the focused segment only.
    let crumbs: [Crumb]?
    let crumbRoom: CGFloat
    let iconOnly: Bool
    /// The pane plays a recording: its icon slot is a speaker that pauses it.
    let playing: Bool
    let select: () -> Void
    let close: () -> Void
    let pause: () -> Void
    @State private var hovering = false

    static let height = Theme.Size.toolbarButton - Theme.Space.s
    static let close = Theme.Space.l

    var body: some View {
        HStack(spacing: Theme.Space.xxs) {
            // The focused segment is told by its ink alone, no capsule of its own: a capsule inside the tab's capsule
            // inside the row made three boxes and left the inner one 3pt to spare (#62). Fading in place as the focus
            // moves: the segments change their ink, they don't slide.
            if let crumbs {
                HStack(spacing: Theme.Space.s) {
                    if playing { speakerButton.foregroundStyle(mark.dot ?? Theme.Palette.chromeSelected) }
                    Breadcrumb(crumbs: crumbs, foldWidth: crumbRoom, maxWidth: crumbRoom)
                }
                .transition(.asymmetric(insertion: .opacity.animation(.snappy), removal: .identity))
            } else {
                HStack(spacing: Theme.Space.tight) {
                    if playing { speakerButton }
                    Button(action: select) {
                        HStack(spacing: Theme.Space.tight) {
                            if !playing { PlaceIcon(place: mark, tint: Theme.Palette.textSecondary) }
                            if !iconOnly { CappedWidth(width: Theme.Size.tabName) { Text(mark.title).lineLimit(1) } }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.pointing(.plain))
                    .help(mark.title)
                    .accessibilityLabel(mark.title)
                }
                .foregroundStyle(Theme.Palette.textSecondary)
                .transition(.asymmetric(insertion: .opacity.animation(.snappy), removal: .identity))
            }
            Button(action: close) {
                Image(systemName: "xmark").font(Theme.Glyph.small)
                    .frame(width: Self.close, height: Self.close)
                    .contentShape(.circle)
            }
            .buttonStyle(.pointing(.plain))
            .foregroundStyle(Theme.Palette.textTertiary)
            .opacity(hovering ? 1 : 0)
            .allowsHitTesting(hovering)
            .help(Text(.panesClose))
            .accessibilityLabel(Text(.panesClose))
        }
        .font(Theme.Typeface.body)
        .padding(.leading, Theme.Space.s)
        .padding(.trailing, Theme.Space.xs)
        .frame(height: Self.height)
        .contentShape(.rect)
        .onTapGesture(perform: select)
        .onHover { hovering = $0 }
    }

    /// Gray on a segment behind, in the course's color on the focused one, like the icon it stands in for.
    var speakerButton: some View {
        Button(action: pause) {
            LineIcon(symbol: TabBar.speakerSymbol).contentShape(.rect)
        }
        .buttonStyle(.pointing(.plain))
        .help(Text(.tabsPause))
        .accessibilityLabel(Text(.tabsPause))
    }
}

/// The thin rule between two segments of a tab.
private struct SegmentRule: View {
    var body: some View {
        Theme.Palette.text.opacity(Theme.Opacity.edge)
            .frame(width: 1, height: Theme.Space.l)
            .padding(.horizontal, Theme.Space.xxs)
    }
}

/// Where the title row's items sit across the window (`TitleRow`), and so where the tabs between them go and how many
/// fit. Only `placement` is watched: what it is worked out from changes with every frame of a live resize, and as the
/// root view's state it redrew the sidebar, every kept tab's screen and the tabs on each one.
@MainActor @Observable final class ToolbarRow {
    /// The tabs at each width they can take, as `TabBar` measured them.
    struct Measures: Equatable {
        var front = TabFit.Front(trail: 0, chrome: 0)
        var others: [TabFit.Other] = []
        var more: CGFloat = 0
    }

    struct Placement: Equatable {
        /// From the back and forward buttons to the first tab.
        var lead: CGFloat
        var fit: TabFit.Layout
        /// The width the front tab's trail is held to; nil while it fits at its own (`TabFit.trail`).
        var trail: CGFloat?
        /// The strip's whole width, the + included.
        var width: CGFloat
        /// Before the new-tab button (`TabFit.newTabSpacing`).
        var newTabSpacing: CGFloat
    }

    private(set) var placement = Placement(lead: 0, fit: TabFit.Layout(iconsOnly: false, shown: 0, hidden: 0), trail: nil, width: 0,
                                           newTabSpacing: TabBar.gap)

    /// Set as the window resizes, before the row lays out (`WindowWidth`): the tabs fit the new width in the same frame.
    /// Measured from the laid-out row instead, it would come a frame behind the window, and a strip too wide for the
    /// row ran the first tab off the panel's edge.
    @ObservationIgnored var windowWidth: CGFloat = 1200 { didSet { settle() } }
    /// Where the row puts its first item (the sidebar button), across the window (`TitleRowEdges.lead`).
    @ObservationIgnored var leadingX = TitleRowEdges.lead(fullScreen: false) { didSet { settle() } }
    /// The search field and the buttons after it, measured. They widen without the window (a course's timer, a
    /// recording's clock), taking their room from the tabs.
    @ObservationIgnored var trailingWidth = ToolbarRow.trailingEstimate { didSet { settle() } }
    /// The content panel's leading edge across the window, where the first tab's capsule lines up.
    @ObservationIgnored var panelEdge: CGFloat = Theme.Size.sidebar { didSet { settle() } }
    @ObservationIgnored var measures = Measures() { didSet { settle() } }

    init() { settle() }

    /// Where the back and forward buttons end across the window.
    var historyEnd: CGFloat { leadingX + Theme.Size.toolbarButton + RootView.historyGap + HistoryButtons.width }

    /// From the back and forward buttons over to the panel's edge; with the sidebar folded the edge is under the
    /// buttons, and the tabs keep a gap after them instead.
    var lead: CGFloat { TabFit.lead(panelEdge: panelEdge, after: historyEnd, gap: Theme.Space.s) }

    /// From the tabs' start to the search field, less a gap before it: the tabs, the menu and the +.
    var room: CGFloat {
        let end = windowWidth - trailingWidth - TitleRowEdges.trailing
        return end - historyEnd - lead - Theme.Space.s
    }

    private func settle() {
        let m = measures
        let plus = CGFloat(TabFit.newTabSpacing(gap: TabBar.gap, button: Theme.Size.toolbarButton, glyph: TabBar.plusInk))
        let space = room - Theme.Size.toolbarButton - plus
        let fit = TabFit.layout(room: space, front: m.front, others: m.others, gap: TabBar.gap, more: m.more)
        // Whole points, down: a held trail follows the width anyway, fractions would only redraw it more often, and
        // rounded up the strip could outgrow the row by one.
        let trail = TabFit.trail(room: space, front: m.front, others: m.others, layout: fit, gap: TabBar.gap, more: m.more)
            .map { $0.rounded(.down) }
        let width = TabFit.width(front: m.front, others: m.others, layout: fit, trail: trail, gap: TabBar.gap, more: m.more)
            + plus + Theme.Size.toolbarButton
        // Whole points wide with the lead, so the strip ends on a whole point and nothing after it sits between pixels.
        let whole = (lead + width).rounded(.down) - lead
        let new = Placement(lead: lead, fit: fit, trail: trail.map { CGFloat($0) }, width: whole, newTabSpacing: plus)
        if new != placement { placement = new }
    }

    /// The search field and five buttons, until they are measured. Not zero: the tabs would take the whole row for the
    /// first frame and run over the search field.
    static let trailingEstimate = Theme.Size.searchField + Theme.Space.s + Theme.Size.toolbarButton * 5 + Theme.Space.xxs * 4
}

/// A short name: its own width up to `width`, cut there. Not `frame(maxWidth:)`, which under `fixedSize` lets the
/// text run at full length past the frame.
private struct CappedWidth: Layout {
    let width: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(ProposedViewSize(width: min(proposal.width ?? width, width), height: proposal.height)) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

private extension View {
    /// The front tab stands out from the frame as a picked choice does; the others are washed like the search field.
    func tabSurface(front: Bool) -> some View {
        background(Theme.Palette.text.opacity(front ? Theme.Opacity.tint : Theme.Opacity.wash), in: .capsule)
            .overlay { Capsule().strokeBorder(Theme.Palette.text.opacity(Theme.Opacity.edge)) }
    }
}
