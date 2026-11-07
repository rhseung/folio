import FolioAI
import FolioDomain
import SwiftUI

/// A tab's panes side by side (#62). Where the row is too narrow for every pane at `Size.paneMin`, the panes pressed
/// longest ago fold into strips in their place (`PaneLayout.folded`); pressing a strip opens it and folds another.
/// A folded pane's screen stays alive under its strip at the width it last had, so it opens as it was left.
struct PaneRow: View {
    let workspace: Workspace
    let panes: TabPanes
    /// The tab in front: only its panes take a press.
    let front: Bool
    let openLink: (Navigator) -> OpenLinkAction
    /// A pane's screen saying it plays a recording (with how to pause it) or has stopped, by the pane's id: the tab
    /// marks the playing pane's icon (`WindowTabs.play`).
    var play: (UUID, (@MainActor () -> Void)?) -> Void = { _, _ in }
    /// Takes a pane out into a tab of its own.
    var newTab: ((Navigator) -> Void)?
    /// How many panes stay open at this width with two panes and with three. It changes only where the width crosses
    /// a count, so a live resize sets it a few times, not every frame.
    @State private var open = [2, 3]
    @State private var sizes = PaneSizes()
    @State private var claude = false
    @State private var claudeAsk: ContextItem?
    @State private var inserts = PaneInserts()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    #if os(macOS)
    /// Between two panels: the same as between a panel and the window's edge.
    static let gap = Theme.Size.panelInset
    #else
    /// A rule between two panes of the split view's detail, which has no panels.
    static let gap: CGFloat = 1
    #endif
    static let space = "panes"

    /// Opens the tab's Claude with an item added to it; nil while no pane is in a course, where it has none.
    var askClaude: (@MainActor (ContextItem) -> Void)? {
        guard panes.navigators.contains(where: { $0.current.course != nil }) else { return nil }
        return { item in
            claudeAsk = item
            claude = true
        }
    }

    var folded: Set<Int> {
        panes.count > 1 ? panes.layout.folded(open: open[min(panes.count, 3) - 2]) : []
    }

    var body: some View {
        let folded = folded
        PaneStack(layout: panes.layout, shares: panes.shares, folded: folded) {
            ForEach(Array(panes.ids.enumerated()), id: \.element) { i, id in
                pane(i, id: id, folded: folded.contains(i))
                if i + 1 < panes.count {
                    divider(after: i, folded: folded)
                }
            }
        }
        .coordinateSpace(.named(Self.space))
        // Over the panes, not in each: one Claude for the tab, which sees them all (#62).
        .overlay(alignment: .bottomTrailing) {
            WindowClaude(workspace: workspace, panes: panes, folded: folded, shown: $claude, incoming: $claudeAsk, inserts: inserts,
                         openLink: openLink)
        }
        #if DEBUG && os(macOS)
        .onChange(of: SnapshotDriver.shared.claudePanel, initial: true) { _, new in claude = new }
        #endif
        .onGeometryChange(for: [Int].self) { proxy in
            [2, 3].map { PaneLayout.openCount($0, room: proxy.size.width, minWidth: Theme.Size.paneMin, strip: Theme.Size.paneStrip, gap: Self.gap) }
        } action: { open = $0 }
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { sizes.row = $0 }
        // Pressing a strip opens it as another folds, together; a new or closed pane slides the others over. A pane
        // folding because the window narrowed comes at once: it comes mid-resize, where a moving pane trails the edge.
        .animation(reduceMotion ? nil : .smooth(duration: 0.34), value: panes.focus)
        .animation(reduceMotion ? nil : .smooth(duration: 0.34), value: panes.ids)
    }

    @ViewBuilder func pane(_ i: Int, id: UUID, folded: Bool) -> some View {
        let navigator = panes.navigators[i]
        // Folded, the screen keeps the width it had open, so it isn't laid out again at the strip's.
        let kept = folded ? sizes.open[id] ?? Theme.Size.paneMin : nil
        ZStack(alignment: .topLeading) {
            PaneScreen(workspace: workspace, navigator: navigator)
                .environment(panes.trails[i])
                .environment(\.openLink, openLink(navigator))
                .environment(\.tabPlaying) { [play] pause in play(id, pause) }
                .environment(\.inPanes, panes.count > 1)
                .environment(\.paneInsert, inserts[id])
                .environment(\.askClaude, askClaude)
                .frame(width: kept, alignment: .topLeading)
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { width in
                    if width >= Theme.Size.paneMin || panes.count == 1 { sizes.open[id] = width }
                }
                .opacity(folded ? 0 : 1)
                .allowsHitTesting(!folded)
                .disabled(folded)
                .accessibilityHidden(folded)
            if folded {
                PaneStrip(mark: workspace.paneMark(of: navigator.current, trail: panes.trails[i]), page: navigator.current.link.anchor?.pageNumber) {
                    panes.press(i)
                }
                .contextMenu { PaneMenu(panes: panes, index: i, newTab: newTab) }
                .transition(.opacity)
            }
        }
        // The focused pane's course color, else the app's.
        .panePanel(ring: panes.count > 1 && i == panes.focus
                   ? navigator.current.course.map { workspace.accent($0).color } ?? Theme.Palette.chromeSelected : nil)
        #if os(macOS)
        .background { PanePress(active: front && !folded) { panes.press(i) } }
        #else
        .simultaneousGesture(TapGesture().onEnded { panes.press(i) })
        #endif
    }

    /// Dragged, it moves the boundary between the two panes beside it; not beside a strip, which has no width to give.
    func divider(after d: Int, folded: Set<Int>) -> some View {
        let enabled = !folded.contains(d) && !folded.contains(d + 1)
        return PaneDivider(enabled: enabled)
            // The panes' own menus, for the two either side: nothing is laid over a pane to hold them.
            .contextMenu {
                ForEach([d, d + 1], id: \.self) { i in
                    Menu(workspace.paneMark(of: panes.navigators[i].current, trail: panes.trails[i]).title) {
                        PaneMenu(panes: panes, index: i, newTab: newTab)
                    }
                }
            }
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.space)).onChanged { drag in
                let widths = panes.layout.widths(room: sizes.row, folded: folded, minWidth: Theme.Size.paneMin, strip: Theme.Size.paneStrip, gap: Self.gap)
                let start = widths.prefix(d).reduce(0, +) + Self.gap * CGFloat(d)
                let pair = widths[d] + widths[d + 1]
                guard enabled, pair > 0 else { return }
                panes.resize(divider: d, to: (drag.location.x - start - Self.gap / 2) / pair)
            })
    }
}

/// Each pane's width as it was last laid out open, and the row's. Not watched: they change every frame of a resize
/// and are read only when a pane folds or a divider moves.
@MainActor final class PaneSizes {
    var open: [UUID: CGFloat] = [:]
    var row: CGFloat = 0
}

/// The panes and the dividers between them, in turn, at the widths `PaneLayout.widths` gives the room. Worked out here,
/// in the same pass as the window's own size, rather than from a width measured into state a frame later.
private struct PaneStack: Layout {
    let layout: PaneLayout
    /// Only so a new share lays the row out again; `layout` has them.
    let shares: [Double]
    let folded: Set<Int>

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let widths = layout.widths(room: bounds.width, folded: folded, minWidth: Theme.Size.paneMin, strip: Theme.Size.paneStrip, gap: PaneRow.gap)
        var x = bounds.minX
        for (k, view) in subviews.enumerated() {
            let width = k % 2 == 0 ? (widths.indices.contains(k / 2) ? widths[k / 2] : 0) : PaneRow.gap
            view.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width
        }
    }
}

/// One pane's screen. Its own view, so a move in one pane redraws only that pane.
private struct PaneScreen: View {
    let workspace: Workspace
    let navigator: Navigator

    var body: some View { ScreenView(workspace: workspace, entry: navigator.current) }
}

/// The gap between two panes, which takes a drag a little past its edges: at its own width it was hard to catch.
private struct PaneDivider: View {
    let enabled: Bool

    var body: some View {
        #if os(macOS)
        Color.clear
            .overlay { Color.clear.frame(width: Theme.Space.m).contentShape(.rect).pointerStyle(enabled ? .columnResize : nil) }
            .accessibilityHidden(true)
        #else
        Theme.Palette.line
            .overlay { Color.clear.frame(width: Theme.Space.l).contentShape(.rect) }
            .accessibilityHidden(true)
        #endif
    }
}

/// A folded pane (A1 in #62): a paper strip in the pane's place with its course's color along the top, what it shows
/// as an icon and its name down the strip, with the page it is at. Pressing it opens the pane.
private struct PaneStrip: View {
    let mark: Crumb
    let page: Int?
    let expand: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: expand) {
            VStack(spacing: Theme.Space.s) {
                PlaceIcon(place: mark)
                Sideways {
                    name.lineLimit(1).rotationEffect(.degrees(90))
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.left.and.right").font(Theme.Glyph.small).foregroundStyle(Theme.Palette.textTertiary)
            }
            .padding(.top, Theme.Space.l)
            .padding(.bottom, Theme.Space.m)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Palette.text.opacity(hovering ? Theme.Opacity.hover : 0))
            .overlay(alignment: .top) {
                // Thicker than a rule: the panel's round corners take most of the strip's width at its top.
                if let dot = mark.dot { dot.frame(height: Theme.Space.xs) }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.pointing(.plain))
        .onHover { hovering = $0 }
        .help(Text(.panesExpand(mark.title)))
        .accessibilityLabel(Text(.panesExpand(mark.title)))
    }

    var name: Text {
        let title = Text(mark.title).font(Theme.Typeface.bodyStrong).foregroundStyle(Theme.Palette.text)
        guard let page else { return title }
        return title + Text(" · ").foregroundStyle(Theme.Palette.textTertiary)
            + Text(.panesPage(page)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
    }
}

/// A line of text turned to run down a narrow strip, as on a book's spine: laid out across the strip's height, then
/// turned, so a long name is cut at the strip's end rather than its width.
private struct Sideways: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = subviews.first?.sizeThatFits(ProposedViewSize(width: proposal.height, height: proposal.width)) ?? .zero
        return CGSize(width: size.height, height: size.width)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let view = subviews.first else { return }
        let size = view.sizeThatFits(ProposedViewSize(width: bounds.height, height: bounds.width))
        view.place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center, proposal: ProposedViewSize(size))
    }
}

/// What a pane offers from its strip and its segment of the tab: closing it, and trading places with a neighbor.
struct PaneMenu: View {
    let panes: TabPanes
    let index: Int
    var newTab: ((Navigator) -> Void)?

    var body: some View {
        Button(.panesClose, systemImage: "xmark") { panes.close(index) }
            .disabled(panes.count < 2)
        if let newTab {
            Button(.panesToTab, systemImage: "macwindow.badge.plus") {
                let navigator = panes.navigators[index]
                if panes.close(index) { newTab(navigator) }
            }
            .disabled(panes.count < 2)
        }
        Divider()
        Button(.panesMoveLeft, systemImage: "arrow.left") { panes.swap(index, index - 1) }
            .disabled(index == 0)
        Button(.panesMoveRight, systemImage: "arrow.right") { panes.swap(index, index + 1) }
            .disabled(index + 1 >= panes.count)
    }
}

/// The icon a place or a pane goes by: a course's mark in its color, else the line icon.
struct PlaceIcon: View {
    let place: Crumb

    var body: some View {
        if let dot = place.dot {
            CourseMark(icon: place.symbol, color: dot)
        } else {
            LineIcon(symbol: place.symbol ?? "questionmark.folder").foregroundStyle(Theme.Palette.chromeIcon)
        }
    }
}

extension Workspace {
    /// A pane's mark on its strip and its segment of the tab: the icon of what it shows (the last step its screen
    /// added, a note's or a file's) in its course's color, and its short name.
    func paneMark(of entry: Navigator.Entry, trail: CrumbTrail?) -> Crumb {
        let place = placeCrumb(of: entry)
        // A course's steps only while the course is shown: they clear as it goes.
        let steps = if case .course = Screen(entry) { trail?.crumbs ?? [] } else { [Crumb]() }
        let symbol = steps.last { $0.symbol != nil }?.symbol ?? place.symbol
        return Crumb(title: tabTitle(of: entry) ?? place.title, symbol: symbol, dot: place.dot)
    }
}

extension AppLink.Anchor {
    var pageNumber: Int? {
        if case .page(let n) = self { n } else { nil }
    }
}

private extension View {
    /// On the Mac each pane is a paper panel of its own on the frame, the focused one's edge a step stronger; the
    /// iPad's split view detail is the paper already.
    /// `ring`: the focused pane's hairline, when the tab has several.
    @ViewBuilder func panePanel(ring: Color?) -> some View {
        #if os(macOS)
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.floating)
        background(Theme.Palette.page, in: shape)
            .clipShape(shape)
            .overlay { shape.strokeBorder(Theme.Palette.lineSoft) }
            // A hairline in the accent says which pane the toolbar and the keys act on, without dimming the others.
            .overlay { if let ring { shape.strokeBorder(ring, lineWidth: 1) } }
        #else
        background(Theme.Palette.page)
            .overlay { if let ring { Rectangle().strokeBorder(ring, lineWidth: 1) } }
        #endif
    }
}

#if os(macOS)
import AppKit

/// Presses the pane it lies under when a click lands anywhere in it. A local event monitor, not a gesture: a note's
/// text and preview page and a PDF take the click in AppKit before SwiftUI sees it. It never takes the click itself.
struct PanePress: NSViewRepresentable {
    let active: Bool
    let press: @MainActor () -> Void

    func makeNSView(context: Context) -> Probe { Probe(press: press) }

    func updateNSView(_ view: Probe, context: Context) {
        view.active = active
        view.press = press
    }

    final class Probe: NSView {
        var active = false
        var press: @MainActor () -> Void
        private var monitor: Any?

        init(press: @escaping @MainActor () -> Void) {
            self.press = press
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
                // Local monitors run on the main thread, with the event the app is handling there.
                nonisolated(unsafe) let event = event
                MainActor.assumeIsolated { self?.check(event) }
                return event
            }
        }

        private func check(_ event: NSEvent) {
            guard active, let window, event.window === window, !isHiddenOrHasHiddenAncestor,
                  bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
            press()
        }
    }
}
#endif
