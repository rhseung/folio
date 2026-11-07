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
    func open(_ navigator: Navigator = Navigator(), fromLink: Bool = false) { open(TabPanes(navigator), fromLink: fromLink) }

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
        // From the tabs still open: a closed tab's screen says it stopped only once the tab is gone.
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
                            newTab: { [tabs] navigator in tabs.open(navigator, fromLink: true) })
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
    }
}

extension EnvironmentValues {
    /// Where a screen says it is playing a recording, so its tab is kept and its pane marked behind the front one.
    @Entry var tabPlaying: @MainActor ((@MainActor () -> Void)?) -> Void = { _ in }
}

#if os(macOS)
/// The tabs at each width they can take, as `TabBar` measures them. Not observed: nothing draws from them, they only
/// feed `ToolbarRow`.
@MainActor final class TabSizes {
    /// The tab in front's trail alone, then its whole capsule with its other segments named and as icons.
    var trail: CGFloat = 0
    var front: CGFloat = 0
    var compactFront: CGFloat = 0
    var more: CGFloat = 0
    private var others: [UUID: [TabForm: CGFloat]] = [:]
    /// False in the toolbar's menu-form copy of the row.
    var inWindow = false

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
#endif

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
        case .grades, .requirements, .people, .codes, .settings, .semester, .course, .card: placeCrumb(of: entry).title
        }
    }
}

#if os(macOS)
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
    @State private var sizes = TabSizes()
    @State private var frames: [UUID: CGRect] = [:]
    @State private var dragged: (id: UUID, start: CGFloat)?
    @State private var dragOffset: CGFloat = 0

    static let gap = Theme.Space.s
    static let icon = Theme.Size.toolbarButton
    static let plus = "plus"
    /// The new-tab glyph's ink, which sets it one gap after the last capsule (`TabFit.newTabSpacing`). Not its image's
    /// width: that has the symbol's side bearings in it, 2 points a side, and the + still sat further off than the
    /// capsules from each other.
    static let plusInk = inkWidth(of: plus, size: Theme.Glyph.toolbarSize)

    static func inkWidth(of symbol: String, size: CGFloat) -> CGFloat {
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
    }

    var body: some View {
        let others = tabs.ids.filter { $0 != tabs.selected }
        // Changes only as the fit or the front tab's trail does, not with every width the window passes through: each
        // redraw of the tabs makes the toolbar rebuild its items' menu form, images and all, and done on every frame
        // of a live resize it held the window to a few frames a second.
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
                #if DEBUG || RESIZE_PROBE
                .background { if id == row.first { ResizeMarker(name: "firstTab") } }
                #endif
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { frames[id] = $0 }
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
                #if DEBUG || RESIZE_PROBE
                .background { ResizeMarker(name: "newTab") }
                #endif
        }
        .coordinateSpace(.named(Self.space))
        .background { measures(others) }
        .background { InWindow { sizes.inWindow = $0; report() } }
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
        // Never wider than the row leaves it: wider, the toolbar put the search field and the buttons in its overflow.
        .frame(width: placement.width, alignment: .leading)
        .padding(.leading, placement.lead)
    }

    static let space = "tabs"

    /// Tells the row what the tabs take, straight from the measures: state set in a measure's callback reached the
    /// body late or not at all, and the row held the front tab to a width it had long outgrown, running the strip
    /// over the search field. Only the row in the window: the toolbar's menu-form copy measures what it showed when
    /// the toolbar last drew it.
    func report() {
        guard sizes.inWindow else { return }
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

    /// The tab in front with several panes: a segment for each, the focused one raised in paper with the breadcrumb,
    /// the others an icon and a short name (icons alone at `compact`); the close button at the end closes the tab.
    func joined(_ panes: TabPanes, crumbRoom: CGFloat, compact: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(panes.ids.enumerated()), id: \.element) { i, _ in
                if i > 0 { SegmentRule() }
                TabSegment(mark: workspace.paneMark(of: panes.navigators[i].current, trail: panes.trails[i]),
                           crumbs: i == panes.focus ? crumbs : nil, crumbRoom: crumbRoom, iconOnly: compact,
                           select: { panes.press(i) }, close: { panes.close(i) })
                    .contextMenu { PaneMenu(panes: panes, index: i) { [tabs] navigator in tabs.open(navigator, fromLink: true) } }
            }
            if tabs.count > 1 { closeButton(tabs.selected).padding(.leading, Theme.Space.xxs) }
        }
        .padding(.horizontal, Theme.Space.xs)
        .frame(height: Theme.Size.toolbarButton)
        .tabSurface(front: true)
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
            let marks = zip(panes.navigators, panes.trails).map { workspace.paneMark(of: $0.current, trail: $1) }
            let playing = panes.ids.map { tabs.playingPanes.contains($0) }
            HStack(spacing: 0) {
                if form == .stacked {
                    Button { tabs.select(id) } label: {
                        HStack(spacing: Theme.Space.xxs) {
                            if playing.contains(true) { speakerIcon } else { PlaceIcon(place: marks[0]) }
                            Text(.panesMoreCount(marks.count - 1)).font(Theme.Typeface.caption).monospacedDigit()
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.pointing(.plain))
                } else {
                    ForEach(marks.indices, id: \.self) { i in
                        if i > 0 { SegmentRule() }
                        Group {
                            if playing[i] {
                                Button { tabs.pause(pane: panes.ids[i]) } label: { speakerIcon.contentShape(.rect) }
                                    .help(Text(.tabsPause))
                                    .accessibilityLabel(Text(.tabsPause))
                            } else {
                                Button { tabs.select(id) } label: { PlaceIcon(place: marks[i]).contentShape(.rect) }
                                    .accessibilityLabel(marks[i].title)
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

    func more(_ hidden: [UUID]) -> some View {
        Menu {
            ForEach(hidden, id: \.self) { id in
                let entry = tabs.navigator(id)?.current ?? Navigator.Entry(link: .place(.today))
                let place = workspace.placeCrumb(of: entry)
                let name = tabs.panes(id).flatMap(workspace.presetName(of:)) ?? workspace.tabTitle(of: entry) ?? place.title
                Button(name, systemImage: tabs.playing.contains(id) ? Self.speakerSymbol : place.symbol ?? CourseMark.defaultIcon) {
                    tabs.select(id)
                }
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
            Button(.tabsMoveToWindow) { moveToWindow(id) }.disabled(tabs.count < 2)
        }
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

    /// Drags a tab along the row; passing a neighbor's middle swaps them, as in Safari.
    func drag(_ id: UUID, row: [UUID]) -> some Gesture {
        DragGesture(minimumDistance: Theme.Space.xs, coordinateSpace: .named(Self.space))
            .onChanged { value in
                guard let frame = frames[id] else { return }
                if dragged?.id != id { dragged = (id, frame.minX) }
                let others = row.filter { $0 != id }
                let before = others.filter { (frames[$0]?.midX ?? 0) < value.location.x }.count
                var rest = tabs.ids.filter { $0 != id }
                let index: Int = if before < others.count { rest.firstIndex(of: others[before]) ?? 0 }
                    else { others.last.flatMap { rest.firstIndex(of: $0) }.map { $0 + 1 } ?? rest.count }
                rest.insert(id, at: index)
                if rest != tabs.ids { tabs.move(id, to: index) }
                // The tab follows the pointer from where it was picked up, whatever place the row now gives it.
                dragOffset = value.translation.width - ((frames[id]?.minX ?? frame.minX) - (dragged?.start ?? frame.minX))
            }
            .onEnded { _ in
                withAnimation(.snappy(duration: 0.2)) {
                    dragged = nil
                    dragOffset = 0
                }
            }
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
    let select: () -> Void
    let close: () -> Void
    @State private var hovering = false

    static let height = Theme.Size.toolbarButton - Theme.Space.s
    static let close = Theme.Space.l

    var body: some View {
        HStack(spacing: Theme.Space.xxs) {
            if let crumbs {
                Breadcrumb(crumbs: crumbs, foldWidth: crumbRoom, maxWidth: crumbRoom)
            } else {
                Button(action: select) {
                    HStack(spacing: Theme.Space.tight) {
                        PlaceIcon(place: mark)
                        if !iconOnly { CappedWidth(width: Theme.Size.tabName) { Text(mark.title).lineLimit(1) } }
                    }
                    .contentShape(.capsule)
                }
                .buttonStyle(.pointing(.plain))
                .foregroundStyle(Theme.Palette.chromeText)
                .help(mark.title)
                .accessibilityLabel(mark.title)
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
        .padding(.leading, crumbs == nil ? Theme.Space.s : Theme.Space.m)
        .padding(.trailing, Theme.Space.xs)
        .frame(height: Self.height)
        .background {
            if crumbs != nil {
                Capsule().fill(Theme.Palette.page).overlay { Capsule().strokeBorder(Theme.Palette.line) }
            }
        }
        .onHover { hovering = $0 }
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

/// Where the toolbar row's items sit across the window, and so where the tabs between them go and how many fit. Only
/// `placement` is watched: what it is worked out from changes with every frame of a live resize, and as the root
/// view's state it redrew the sidebar, every kept tab's screen and the tabs on each one.
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
    @ObservationIgnored var windowWidth: CGFloat = 1200 { didSet { settle() } }
    /// Where the row put its first item (the sidebar button), across the window.
    @ObservationIgnored var leadingX: CGFloat? { didSet { settle() } }
    /// The search field and the buttons after it, measured, until the row has placed them.
    @ObservationIgnored var trailingWidth = ToolbarRow.trailingEstimate { didSet { settle() } }
    /// The content panel's leading edge across the window, where the first tab's capsule lines up.
    @ObservationIgnored var panelEdge: CGFloat = Theme.Size.sidebar { didSet { settle() } }
    @ObservationIgnored var measures = Measures() { didSet { settle() } }
    /// From the end of the search field and its buttons to the window's trailing edge, as the row put them. It holds as
    /// the window's width changes, the group pinned to the end, so the tabs' room follows the width at once. The
    /// group's place itself is known only a turn after the row laid out (`WindowOffset`): fitted to it, the tabs ran a
    /// frame behind the window, and a strip too wide for the row pushed the first tab off the panel's edge. Not the
    /// whole inset: the group widens without the window (a course's timer, a recording's clock), and a held inset
    /// kept the tabs' room while the group went into the overflow menu, where it has no place to correct it.
    @ObservationIgnored private var trailingGap: CGFloat?

    init() { settle() }

    /// The search field's place, as the row reports it, with the window's width at the time.
    func placeTrailing(_ x: CGFloat?, in width: CGFloat) {
        // Dropped into the overflow menu, the field has no place; the last one still says where it belongs. Forgetting
        // it fell back to an estimate, which could push the field out again.
        guard let x else { return }
        let gap = width - x - trailingWidth
        guard gap != trailingGap else { return }
        trailingGap = gap
        settle()
    }

    /// Where the back and forward buttons end across the window, the tabs' item placed where the row put it.
    var historyEnd: CGFloat { (leadingX ?? Self.leadingEstimate) + Theme.Size.toolbarButton + RootView.historyGap + HistoryButtons.width }

    /// From the back and forward buttons over to the panel's edge; with the sidebar folded the edge is under the
    /// buttons, and the tabs keep a gap after them instead.
    var lead: CGFloat { TabFit.lead(panelEdge: panelEdge, after: historyEnd, gap: Theme.Space.s) }

    /// From the tabs' start to the search field, less a gap before it: the tabs, the menu and the +.
    var room: CGFloat {
        let end = windowWidth - trailingWidth - (trailingGap ?? Self.toolbarGaps)
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
        // The item whole points wide, the lead and the strip together: half a point over, the toolbar moved the item
        // by half a point, the row reported the new place, the lead took up the half, and the item went back, every
        // few frames of a resize.
        let whole = (lead + width).rounded(.down) - lead
        let new = Placement(lead: lead, fit: fit, trail: trail.map { CGFloat($0) }, width: whole, newTabSpacing: plus)
        if new != placement { placement = new }
    }

    /// The sidebar button's place when the row hasn't said yet: after the window's buttons, measured.
    static let leadingEstimate: CGFloat = 84
    /// Between the items and after the last to the window's edge, measured in a window snapshot.
    static let toolbarGaps: CGFloat = 32
    /// The search field and five buttons, until the item is measured. Not zero: the tabs then took the whole row and
    /// pushed the search field into the toolbar's overflow menu, where it was never measured.
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
#endif
