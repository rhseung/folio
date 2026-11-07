import FolioDomain
import SwiftUI

/// One window's tabs, each with its own history. The window draws them in its toolbar row itself rather than as
/// AppKit window tabs, whose bar took a row of its own over the frame.
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
    private var navigators: [UUID: Navigator]
    /// Each tab's breadcrumb steps, which its screen sets while alive. With one trail for the window, a screen kept
    /// behind would keep its steps in the front tab's trail.
    private var trails: [UUID: CrumbTrail]
    /// The tabs whose screens are alive, the one in front among them.
    private(set) var alive: Set<UUID>
    /// When each tab last went behind another.
    @ObservationIgnored private var left: [UUID: Date] = [:]
    /// The tabs playing a recording, each with how to pause it from the strip. `TabKeep` keeps them alive: dropping the
    /// screen would stop the audio.
    private(set) var playing: Set<UUID> = []
    @ObservationIgnored private var pauses: [UUID: @MainActor () -> Void] = [:]
    /// Closing the last tab closes the window, which the window hands over once it has one.
    @ObservationIgnored var closeWindow: @MainActor () -> Void = {}
    @ObservationIgnored var now: @MainActor () -> Date = { .now }
    @ObservationIgnored var policy = WindowTabs.keep

    /// How many screens wait behind the front tab and for how long. A note tab costs most: its preview's page runs in a
    /// WebKit process of its own, about 80MB for a usual note and 270MB for a long one with math and diagrams, against
    /// 10MB for a course page (measured with `TabMemoryProbe`; the numbers are in #304).
    static let keep = TabKeep.Policy(limit: 3, idle: 30 * 60)

    init(_ first: Navigator) {
        let id = UUID()
        strip = TabStrip(id)
        navigators = [id: first]
        trails = [id: CrumbTrail()]
        alive = [id]
    }

    var selected: UUID { strip.selected }
    var ids: [UUID] { strip.tabs }
    var count: Int { strip.tabs.count }
    var current: Navigator { navigators[strip.selected] ?? Navigator() }

    func navigator(_ id: UUID) -> Navigator? { navigators[id] }
    func trail(_ id: UUID) -> CrumbTrail? { trails[id] }

    /// `fromLink`: beside the tab in front rather than last.
    func open(_ navigator: Navigator = Navigator(), fromLink: Bool = false) {
        let id = UUID()
        navigators[id] = navigator
        trails[id] = CrumbTrail()
        strip.open(id, afterSelected: fromLink)
    }

    func select(_ id: UUID) { strip.select(id) }
    func select(number n: Int) { strip.select(number: n) }
    func selectNext() { strip.selectNext() }
    func selectPrevious() { strip.selectPrevious() }
    func move(_ id: UUID, to index: Int) { strip.move(id, to: index) }

    func close(_ id: UUID) {
        guard strip.close(id) else { return closeWindow() }
        navigators[id] = nil
        trails[id] = nil
    }

    func closeSelected() { close(selected) }

    /// A tab's screen saying it plays (with how to pause it) or has stopped (nil).
    func play(_ id: UUID, pause: (@MainActor () -> Void)?) {
        pauses[id] = pause
        let on = pause != nil && strip.tabs.contains(id)
        if on != playing.contains(id) { if on { playing.insert(id) } else { playing.remove(id) } }
    }

    func pause(_ id: UUID) { pauses[id]?() }

    func closeOthers(than id: UUID) {
        strip.closeOthers(than: id)
        navigators = navigators.filter { $0.key == id }
        trails = trails.filter { $0.key == id }
    }

    /// Takes a tab out for a window of its own; nil for the last one, which is the window already.
    func take(_ id: UUID) -> Navigator? {
        guard count > 1, let navigator = navigators[id], strip.close(id) else { return nil }
        navigators[id] = nil
        trails[id] = nil
        return navigator
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
/// screen's ⌘S or ⌘E, or the zoom keys of a file it shows, would otherwise act on a page no one sees. Each screen
/// keeps its own breadcrumb steps and moves its own tab when it opens a link.
struct TabScreens: View {
    let tabs: WindowTabs
    let workspace: Workspace
    let openLink: (Navigator) -> OpenLinkAction
    @State private var sizes = ScreenSizes()

    var body: some View {
        ZStack {
            // In the strip's order, so a screen keeps its place in the stack, and its state, as others come and go.
            ForEach(tabs.ids.filter { tabs.alive.contains($0) }, id: \.self) { id in
                if let navigator = tabs.navigator(id) {
                    let front = id == tabs.selected
                    // A screen behind keeps the size it last had in front, so resizing the window lays out only the
                    // one in front: a note's text and preview page reflowing out of sight made each frame of a live
                    // resize wait on every kept tab. It takes the window's size again when it comes back.
                    let kept = front ? nil : sizes[id]
                    TabScreen(workspace: workspace, navigator: navigator)
                        .environment(tabs.trail(id))
                        .environment(\.tabPlaying) { [tabs] pause in tabs.play(id, pause: pause) }
                        .environment(\.openLink, openLink(navigator))
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
    /// Where a screen says it is playing a recording, so its tab is kept and marked behind the front one.
    @Entry var tabPlaying: @MainActor ((@MainActor () -> Void)?) -> Void = { _ in }
}

/// The tabs at full width, as `TabBar` measures them. Not observed: nothing draws from them, they only feed `ToolbarRow`.
@MainActor final class TabSizes {
    var front: CGFloat = 0
    var more: CGFloat = 0
    var others: [UUID: CGFloat] = [:]
    /// False in the toolbar's menu-form copy of the row.
    var inWindow = false
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

/// One tab's screen. Its own view, so a move in one tab redraws only that tab's screen.
private struct TabScreen: View {
    let workspace: Workspace
    let navigator: Navigator

    var body: some View { ScreenView(workspace: workspace, entry: navigator.current) }
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
/// The window's tabs in its toolbar row: the tab in front is the breadcrumb of where it is, with a close button; the
/// others are an icon and a short name, then icons alone, then a menu, as the row runs out (`TabFit`). A + at the end
/// opens Today in a new tab.
struct TabBar: View {
    let tabs: WindowTabs
    let workspace: Workspace
    /// The tab in front's whole trail: its screen, then what the screen added.
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
                            front(crumbRoom: trail).frame(width: trail + frontChrome)
                        } else {
                            front(crumbRoom: .infinity).fixedSize()
                        }
                    } else {
                        // At their measured width: `TabFit` already made room, and squeezed they'd cut their names.
                        tab(id, iconOnly: fit.iconsOnly).fixedSize()
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
            sizes.others = sizes.others.filter { open.contains($0.key) }
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
        let measures = ToolbarRow.Measures(front: sizes.front, others: others.map { Double(sizes.others[$0] ?? Self.icon) },
                                           more: sizes.more, chrome: frontChrome)
        if measures != toolbar.measures { toolbar.measures = measures }
    }

    /// The front tab's capsule around its trail: the leading inset and the close button with its gap.
    var frontChrome: CGFloat {
        Theme.Space.m + (tabs.count > 1 ? Theme.Space.xs + Self.closeSize + Theme.Space.xs : Theme.Space.m)
    }

    static let closeSize = Theme.Size.tile

    @ViewBuilder func front(crumbRoom: CGFloat) -> some View {
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

    func tab(_ id: UUID, iconOnly: Bool) -> some View {
        let entry = tabs.navigator(id)?.current ?? Navigator.Entry(link: .place(.today))
        let title = workspace.tabTitle(of: entry)
        let playing = tabs.playing.contains(id)
        return Button { tabs.select(id) } label: {
            label(entry, title: iconOnly ? nil : title, playing: playing)
        }
        .buttonStyle(.pointing(.plain))
        // Its own button over the room the label leaves it: a button inside the tab's label would select the tab.
        .overlay(alignment: .trailing) { if playing && !iconOnly { speaker(id) } }
        .help(title ?? workspace.placeCrumb(of: entry).title)
        .accessibilityLabel(title ?? workspace.placeCrumb(of: entry).title)
    }

    /// A tab behind the front one: its icon, and its name unless it has none or the row is short. Playing a recording,
    /// it leaves room at its end for the speaker, set as the front tab sets its close button, or shows the speaker in
    /// place of its icon when the row is short.
    @ViewBuilder func label(_ entry: Navigator.Entry, title: String?, playing: Bool = false) -> some View {
        let place = workspace.placeCrumb(of: entry)
        Group {
            if let title {
                HStack(spacing: Theme.Space.tight) {
                    icon(place)
                    CappedWidth(width: Theme.Size.tabName) { Text(title).lineLimit(1) }
                }
                .padding(.leading, Theme.Space.s)
                .padding(.trailing, playing ? Theme.Space.xs + Self.closeSize + Theme.Space.xs : Theme.Space.m)
            } else if playing {
                LineIcon(symbol: Self.speakerSymbol).foregroundStyle(Theme.Palette.chromeIcon).frame(width: Self.icon)
            } else {
                icon(place).frame(width: Self.icon)
            }
        }
        .font(Theme.Typeface.body)
        .foregroundStyle(Theme.Palette.chromeText)
        .frame(height: Theme.Size.toolbarButton)
        .tabSurface(front: false)
        .contentShape(.capsule)
    }

    @ViewBuilder func icon(_ place: Crumb) -> some View {
        if let dot = place.dot {
            CourseMark(icon: place.symbol, color: dot)
        } else {
            LineIcon(symbol: place.symbol ?? "questionmark.folder").foregroundStyle(Theme.Palette.chromeIcon)
        }
    }

    static let speakerSymbol = "speaker.wave.2.fill"

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
                Button(workspace.tabTitle(of: entry) ?? place.title,
                       systemImage: tabs.playing.contains(id) ? Self.speakerSymbol : place.symbol ?? CourseMark.defaultIcon) { tabs.select(id) }
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

    /// What every tab would take at full width, drawn once out of sight: a tab drawn as an icon can't tell how wide
    /// its name would make it.
    func measures(_ others: [UUID]) -> some View {
        ZStack {
            front(crumbRoom: .infinity).fixedSize()
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { sizes.front = $0; report() }
            ForEach(others, id: \.self) { id in
                let entry = tabs.navigator(id)?.current ?? Navigator.Entry(link: .place(.today))
                label(entry, title: workspace.tabTitle(of: entry), playing: tabs.playing.contains(id)).fixedSize()
                    .onGeometryChange(for: CGFloat.self, of: \.size.width) { sizes.others[id] = $0; report() }
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

/// Where the toolbar row's items sit across the window, and so where the tabs between them go and how many fit. Only
/// `placement` is watched: what it is worked out from changes with every frame of a live resize, and as the root
/// view's state it redrew the sidebar, every kept tab's screen and the tabs on each one.
@MainActor @Observable final class ToolbarRow {
    /// The tabs at full width, as `TabBar` measured them.
    struct Measures: Equatable {
        var front: CGFloat = 0
        var others: [Double] = []
        var more: CGFloat = 0
        /// The front tab's capsule around its trail.
        var chrome: CGFloat = 0
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
        let fit = TabFit.layout(room: space, selected: m.front, others: m.others, icon: TabBar.icon, gap: TabBar.gap, more: m.more)
        // Whole points, down: a held trail follows the width anyway, fractions would only redraw it more often, and
        // rounded up the strip could outgrow the row by one.
        let trail = TabFit.trail(room: space, selected: m.front, others: m.others, layout: fit, icon: TabBar.icon, gap: TabBar.gap,
                                 more: m.more, chrome: m.chrome).map { $0.rounded(.down) }
        let width = TabFit.width(selected: m.front, others: m.others, layout: fit, trail: trail, icon: TabBar.icon, gap: TabBar.gap,
                                 more: m.more, chrome: m.chrome) + plus + Theme.Size.toolbarButton
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
