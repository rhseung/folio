import FolioAI
import FolioDomain
import SwiftUI

/// A tab's panes side by side (#62). Where the row is too narrow for every pane at `Size.paneMin`, a run of them stays
/// in place and the rest fold into a bundle at either end, one strip each however many it holds (`PaneLayout.fold`,
/// 2026-11-12 사용자); choosing a pane from a bundle slides the run to it. A pane folded by hand (칸 접기) is a hatched
/// strip in its place until it is pressed. A folded pane's screen stays alive at the width it last had, so it opens as
/// it was left.
struct PaneRow: View {
    let workspace: Workspace
    let panes: TabPanes
    /// The tab in front: only its panes take a press.
    let front: Bool
    let openLink: (Navigator) -> OpenLinkAction
    /// A pane's screen saying it plays a recording (with how to pause it) or has stopped, by the pane's id: the tab
    /// marks the playing pane's icon (`WindowTabs.play`).
    var play: (UUID, (@MainActor () -> Void)?) -> Void = { _, _ in }
    /// Takes a pane out into a tab of its own, with the columns it had hidden.
    var newTab: ((Navigator, ColumnPrefs) -> Void)?
    @State private var sizes = PaneSizes()
    @State private var drag = PaneDrag()
    /// Back to false however the drag ends: a drag the system cancels (the window losing the pointer) has no end.
    @GestureState private var dragging = false
    @State private var claude = false
    @State private var claudeAsk: ContextItem?
    @State private var inserts = PaneInserts()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Between two panels: the same as between a panel and the window's edge.
    static let gap = Theme.Size.panelInset
    static let space = "panes"

    /// Nil while no pane is in a course, where the tab has no Claude.
    var askClaude: (@MainActor (ContextItem) -> Void)? {
        guard panes.navigators.contains(where: { $0.current.course != nil }) else { return nil }
        return { item in
            claudeAsk = item
            claude = true
        }
    }

    var folded: Set<Int> { panes.folded }

    var body: some View {
        let fold = panes.fold
        let folded = fold.folded
        let gaps = fold.gaps(1)
        // The panes go in built, so a drag redraws the stack alone: were the shares read here, every frame of it would
        // run this body again, and each pane's screen with it for the closures it is handed anew (`openLink`).
        LivePaneStack(panes: panes, drag: drag, fold: fold) {
            // The pane's place found again from its ID: SwiftUI can run a closed pane's view once more with the place
            // it had, past the end of the panes (as it did the tab bar's segments, 2026-11-08).
            ForEach(panes.ids, id: \.self) { id in
                if let i = panes.ids.firstIndex(of: id) {
                    pane(i, id: id, look: fold.count == panes.count ? fold.look(i) : .open)
                    if i + 1 < panes.count {
                        divider(after: i, folded: folded, shown: gaps.indices.contains(i) && gaps[i] > 0)
                    }
                }
            }
        }
        .coordinateSpace(.named(Self.space))
        .background { SessionLayoutSaver(workspace: workspace, panes: panes) }
        .onChange(of: dragging) { _, now in if !now { dropped() } }
        // Over the panes, not in each: one Claude for the tab, which sees them all (#62).
        .overlay(alignment: .bottomTrailing) {
            WindowClaude(workspace: workspace, panes: panes, folded: folded, shown: $claude, incoming: $claudeAsk, inserts: inserts,
                         openLink: openLink)
        }
        #if DEBUG && os(macOS)
        .onChange(of: SnapshotDriver.shared.claudePanel, initial: true) { _, new in claude = new }
        #endif
        // The tab turns the width into how many panes stay open, and is watched only when that changes.
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width in
            sizes.row = width
            panes.measure(width)
        }
        // Pressing a strip opens it as another folds, together; a new or closed pane slides the others over. A pane
        // folding because the window narrowed comes at once: it comes mid-resize, where a moving pane trails the edge.
        .animation(reduceMotion ? nil : Theme.Motion.pane, value: panes.focus)
        .animation(reduceMotion ? nil : Theme.Motion.pane, value: panes.collapsed)
        .animation(reduceMotion ? nil : Theme.Motion.pane, value: panes.ids)
    }

    @ViewBuilder func pane(_ i: Int, id: UUID, look: PaneLayout.Fold.Look) -> some View {
        let folded = look != .open
        let navigator = panes.navigators[i]
        // Folded, the screen keeps the width it had open, so it isn't laid out again at the strip's.
        let kept = folded ? sizes.open[id] ?? Theme.Size.paneMin : nil
        ZStack(alignment: .topLeading) {
            PaneScreen(workspace: workspace, navigator: navigator)
                .environment(panes.trails[i])
                .environment(\.openLink, openLink(navigator))
                .environment(\.tabPlaying) { [play] pause in play(id, pause) }
                .environment(\.paneFocused, i == panes.focus)
                .environment(\.columnPrefs, panes.columns[i])
                .environment(\.paneInsert, inserts[id])
                .environment(\.paneNotes, PaneNotes(panes: panes, pane: id))
                .environment(\.askClaude, askClaude)
                .modifier(PaneScreenWidth(panes: panes, index: i, kept: kept, sizes: sizes))
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { width in
                    if width >= Theme.Size.paneMin || panes.count == 1 { sizes.open[id] = width }
                }
                .opacity(folded ? 0 : 1)
                .allowsHitTesting(!folded)
                .disabled(folded)
                .accessibilityHidden(folded)
            switch look {
            case .open, .hidden:
                EmptyView()
            case .strip:
                strip(i, byHand: true)
            case .bundle(let held) where held.count == 1:
                strip(i, byHand: false)
            case .bundle(let held):
                PaneBundle(panes: panes, held: held.map { j in
                    PaneBundle.Held(index: j, mark: workspace.paneMark(of: panes.navigators[j].current, trail: panes.trails[j]))
                }, trailing: held.first.map { $0 > panes.focus } ?? false, newTab: newTab)
                .transition(.opacity)
            }
        }
        .panePanel(ring: panes.count > 1 && i == panes.focus
                   ? navigator.current.course.map { workspace.accent($0).color } ?? Theme.Palette.chromeSelected : nil)
        // In a bundle, drawn by its strip: the screen stays alive, unseen, for when it is chosen.
        .opacity(look == .hidden ? 0 : 1)
        .accessibilityHidden(look == .hidden)
        #if os(macOS)
        .background { PanePress(active: front && !folded) { panes.press(i) } }
        #else
        // Only on an open pane: a bundle's strip lists its panes, and a tap pressing the pane it stands in for would
        // move the run under the list.
        .simultaneousGesture(TapGesture().onEnded { panes.press(i) }, including: folded ? .subviews : .all)
        #endif
    }

    func strip(_ i: Int, byHand: Bool) -> some View {
        let navigator = panes.navigators[i]
        return PaneStrip(mark: workspace.paneMark(of: navigator.current, trail: panes.trails[i]), page: navigator.current.link.anchor?.pageNumber,
                         byHand: byHand) {
            panes.press(i)
        }
        .contextMenu { PaneMenu(panes: panes, index: i, newTab: newTab) }
        .transition(.opacity)
    }

    /// Dragged, it moves the boundary between the two panes beside it; not beside a strip, which has no width to give.
    /// `shown`: false beside a pane in a bundle, where the row draws no gap, and nothing there takes a click.
    func divider(after d: Int, folded: Set<Int>, shown: Bool) -> some View {
        let enabled = !folded.contains(d) && !folded.contains(d + 1)
        return PaneDivider(enabled: enabled, front: front, even: panes.even)
            .allowsHitTesting(shown)
            #if os(macOS) && (DEBUG || RESIZE_PROBE)
            .background { if front && d == 0 { ResizeMarker(name: "divider") } }
            #endif
            // The panes' own menus, for the two either side: nothing is laid over a pane to hold them. On the iPad a long
            // press is how the panes are evened: a double tap on so thin a target was hard to hit and to find.
            .contextMenu {
                Button(.panesEven, systemImage: "rectangle.split.3x1", action: panes.even)
                Divider()
                ForEach([d, d + 1], id: \.self) { i in
                    Menu(workspace.paneMark(of: panes.navigators[i].current, trail: panes.trails[i]).title) {
                        PaneMenu(panes: panes, index: i, newTab: newTab)
                    }
                }
            }
            // Past a click's wobble, so a double click that moves a point or two is still a double click, and by how
            // far it went rather than where it is, so the divider doesn't jump to the pointer from where it was caught in
            // its margin.
            .gesture(DragGesture(minimumDistance: Self.wobble, coordinateSpace: .named(Self.space))
                .updating($dragging) { _, dragging, _ in dragging = true }
                .onChanged { drag in if enabled { dragged(d, by: drag.translation.width, folded: folded) } }
                .onEnded { drag in
                    if enabled { dragged(d, by: drag.translation.width, folded: folded) }
                    dropped()
                })
            #if os(macOS) && (DEBUG || RESIZE_PROBE)
            .onAppear { if front && d == 0 { PaneDragHook.shared.row = self } }
            #endif
    }

    static let wobble: CGFloat = 4

    /// The two panes beside the divider are laid out at every width it passes, as a browser's page follows a window's
    /// edge (2026-11-08 사용자). The widths are drawn from `drag` alone until it ends: the tab hears of them once, when
    /// it is dropped, so the drag lays out the stack and not the whole row with every screen's closures made anew.
    func dragged(_ d: Int, by translation: CGFloat, folded: Set<Int>) {
        if drag.from == nil {
            let widths = panes.layout.widths(room: sizes.row, fold: panes.fold, minWidth: Theme.Size.paneMin, strip: Theme.Size.paneStrip, gap: Self.gap)
            guard widths.indices.contains(d + 1) else { return }
            drag.from = PaneDrag.Start(divider: d, layout: panes.layout, left: widths[d], pair: widths[d] + widths[d + 1])
        }
        guard let from = drag.from, from.pair > 0 else { return }
        var live = from.layout
        live.resize(divider: d, to: (from.left + translation) / from.pair)
        if live != drag.live { drag.live = live }
    }

    /// A drag ends here twice, so the second call finds none under way and does nothing.
    func dropped() {
        if let from = drag.from, let live = drag.live, live.panes.count == panes.count {
            let d = from.divider
            panes.resize(divider: d, to: live.shares[d] / (live.shares[d] + live.shares[d + 1]))
        }
        drag.from = nil
        drag.live = nil
    }
}

@MainActor @Observable final class PaneDrag {
    struct Start {
        var divider: Int
        var layout: PaneLayout
        /// The left pane's width and the two panes' together, as they were drawn when the drag began.
        var left: CGFloat
        var pair: CGFloat
    }

    @ObservationIgnored var from: Start?
    var live: PaneLayout?
}

#if os(macOS) && (DEBUG || RESIZE_PROBE)
/// The first divider of the tab in front, for `ResizeProbe` to drag the way the gesture does: synthetic mouse events
/// lose the drag whenever the real pointer moves.
@MainActor final class PaneDragHook {
    static let shared = PaneDragHook()
    var row: PaneRow?

    func move(by translation: CGFloat) { row.map { $0.dragged(0, by: translation, folded: $0.folded) } }

    func end() { row?.dropped() }
}
#endif

/// Each pane's width as it was last laid out open, and the row's. Not watched: they change every frame of a resize
/// and are read only when a pane folds or a divider moves.
@MainActor final class PaneSizes {
    var open: [UUID: CGFloat] = [:]
    var row: CGFloat = 0
}

/// Its own view, so only it watches a drag's widths.
private struct LivePaneStack<Content: View>: View {
    let panes: TabPanes
    let drag: PaneDrag
    let fold: PaneLayout.Fold
    @ViewBuilder let content: Content

    var body: some View {
        // A pane opened or closed under the drag ends it: its widths were for the panes there were.
        let live = drag.live.flatMap { $0.panes.count == panes.count ? $0 : nil }
        let glide = live == nil ? panes.glide.flatMap { $0.from.panes.count == panes.count ? $0 : nil } : nil
        // Always in the timeline, paused but for a glide: put in only for one, the panes would be built anew.
        TimelineView(.animation(paused: glide == nil)) { context in
            PaneStack(layout: live ?? panes.layout, shares: live?.shares ?? panes.shares, fold: fold,
                      from: glide.map { ($0.from, $0.fold) }, progress: glide?.progress(at: context.date) ?? 1) { content }
        }
    }
}

/// The widths are worked out here, in the same pass as the window's own size, rather than from a width measured into
/// state a frame later.
private struct PaneStack: Layout {
    let layout: PaneLayout
    /// Only so a new share lays the row out again; `layout` has them.
    let shares: [Double]
    let fold: PaneLayout.Fold
    /// A glide's start, and how far it has come from it to `layout`.
    var from: (layout: PaneLayout, fold: PaneLayout.Fold)?
    var progress = 1.0

    static func sizes(_ layout: PaneLayout, _ fold: PaneLayout.Fold, room: CGFloat) -> (widths: [Double], gaps: [Double]) {
        let drawn = fold.count == layout.panes.count ? fold : layout.unfolded
        return (layout.widths(room: room, fold: drawn, minWidth: Theme.Size.paneMin, strip: Theme.Size.paneStrip, gap: PaneRow.gap), drawn.gaps(PaneRow.gap))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    // The row's own edges. Left to the default, a parent's question about an edge (a ZStack's) placed every pane and
    // laid out its screen once more for the answer.
    func explicitAlignment(of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGFloat? { nil }

    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGFloat? { nil }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var (widths, gaps) = Self.sizes(layout, fold, room: bounds.width)
        if let from, progress < 1 {
            let start = Self.sizes(from.layout, from.fold, room: bounds.width)
            widths = zip(start.widths, widths).map { $0 + ($1 - $0) * progress }
            gaps = zip(start.gaps, gaps).map { $0 + ($1 - $0) * progress }
        }
        var x = bounds.minX
        for (k, view) in subviews.enumerated() {
            let i = k / 2
            let width = k % 2 == 0 ? (widths.indices.contains(i) ? widths[i] : 0) : (gaps.indices.contains(i) ? gaps[i] : PaneRow.gap)
            view.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width
        }
    }
}

/// A pane's screen at a width of its own where the panel's isn't the one to lay it out at: its open width while it is
/// a strip, so folding doesn't lay it out again, and its end width while a glide opens it, so it is laid out once and
/// the panel's edge slides over it rather than widening it from a strip's width frame by frame.
private struct PaneScreenWidth: ViewModifier {
    let panes: TabPanes
    let index: Int
    let kept: CGFloat?
    let sizes: PaneSizes

    func body(content: Content) -> some View {
        let width = kept ?? opening
        // At once: a press animates the row, and a screen animated to a new width animates its own layout with it.
        content.frame(width: width, alignment: .topLeading).animation(nil, value: width)
    }

    // Read here rather than in the row, so a glide starting and ending redraws this frame alone.
    var opening: CGFloat? {
        guard let glide = panes.glide, glide.fold.folded.contains(index) else { return nil }
        guard !panes.folded.contains(index) else { return nil }
        let widths = panes.layout.widths(room: sizes.row, fold: panes.fold, minWidth: Theme.Size.paneMin, strip: Theme.Size.paneStrip, gap: PaneRow.gap)
        return widths.indices.contains(index) ? widths[index] : nil
    }
}

/// Its own view, so a move in one pane redraws only that pane.
private struct PaneScreen: View {
    let workspace: Workspace
    let navigator: Navigator

    var body: some View { ScreenView(workspace: workspace, entry: navigator.current) }
}

/// The gap between two panes, which takes a drag a little past its edges: at its own width it was hard to catch.
/// Clicked twice on the Mac, it evens the panes.
private struct PaneDivider: View {
    let enabled: Bool
    /// In the tab in front: one behind sees no clicks.
    let front: Bool
    let even: @MainActor () -> Void

    var body: some View {
        #if os(macOS)
        Color.clear
            .overlay {
                Color.clear.frame(width: Theme.Space.m).contentShape(.rect).pointerStyle(enabled ? .columnResize : nil)
                    // From the window's events like a pane's press, not a tap gesture: beside the divider's drag, a
                    // second click is the drag's to take.
                    .background { PanePress(active: front, clicks: 2, press: even) }
            }
            .accessibilityHidden(true)
        #else
        Theme.Palette.line
            .overlay { Color.clear.frame(width: Theme.Space.l).contentShape(.rect) }
            .accessibilityHidden(true)
        #endif
    }
}

/// A folded pane, design A1 in #62.
private struct PaneStrip: View {
    let mark: Crumb
    let page: Int?
    /// Folded by hand ("칸 접기"): hatched, so it reads as put aside rather than out of room.
    var byHand = false
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
            .background { if byHand { PaneHatch() } }
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

private struct PaneHatch: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            let step = Theme.Space.s
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += step
            }
            context.stroke(path, with: .color(Theme.Palette.lineSoft), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

/// A bundle of two or more panes at the row's end (#62, 2026-11-12 사용자). Each listed row's menu is the pane's own
/// strip menu, as is the strip's menu for each pane.
private struct PaneBundle: View {
    struct Held: Identifiable {
        let index: Int
        let mark: Crumb
        var id: Int { index }
    }

    let panes: TabPanes
    let held: [Held]
    /// At the row's trailing end, so the list opens toward the panes.
    let trailing: Bool
    var newTab: ((Navigator, ColumnPrefs) -> Void)?
    @State private var listing = false
    @State private var hovering = false

    /// The list opens toward the panes. A Mac reads the edge as the bundle's side the popover stands on; an iPad as
    /// the side its arrow points (UIKit's arrow direction), so the same edge put the list off the screen's edge there.
    private var listEdge: Edge {
        #if os(macOS)
        trailing ? .leading : .trailing
        #else
        trailing ? .trailing : .leading
        #endif
    }

    var body: some View {
        Button { listing = true } label: {
            VStack(spacing: Theme.Space.s) {
                // Overlapping, as a stack of cards: each icon a step down the last.
                VStack(spacing: -Theme.Space.s) {
                    ForEach(held.prefix(3)) { PlaceIcon(place: $0.mark) }
                }
                Sideways {
                    Text(.panesBundleCount(held.count)).font(Theme.Typeface.bodyStrong).foregroundStyle(Theme.Palette.text)
                        .lineLimit(1).rotationEffect(.degrees(90))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(Theme.Glyph.small).foregroundStyle(Theme.Palette.textTertiary)
            }
            .padding(.top, Theme.Space.l)
            .padding(.bottom, Theme.Space.m)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Palette.text.opacity(hovering || listing ? Theme.Opacity.hover : 0))
            .contentShape(.rect)
        }
        .buttonStyle(.pointing(.plain))
        .onHover { hovering = $0 }
        .help(Text(.panesBundleList(held.count)))
        .accessibilityLabel(Text(.panesBundleList(held.count)))
        .contextMenu {
            ForEach(held) { item in
                Menu(item.mark.title) { PaneMenu(panes: panes, index: item.index, newTab: newTab) }
            }
        }
        .popover(isPresented: $listing, arrowEdge: listEdge) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                ForEach(held) { item in
                    Button {
                        listing = false
                        panes.press(item.index)
                    } label: {
                        HStack(spacing: Theme.Space.s) {
                            PlaceIcon(place: item.mark)
                            Text(item.mark.title).font(Theme.Typeface.body).foregroundStyle(Theme.Palette.text).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, Theme.Space.s)
                        .frame(minHeight: Theme.Size.rowHeight)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.pointing(.plain))
                    .accessibilityLabel(Text(.panesExpand(item.mark.title)))
                    .contextMenu { PaneMenu(panes: panes, index: item.index, newTab: newTab) }
                }
            }
            .padding(Theme.Space.xs)
            .frame(minWidth: Theme.Size.paneMin / 2, alignment: .leading)
            .presentationCompactAdaptation(.popover)
        }
        #if DEBUG
        .onChange(of: PaneBundleHook.shared.listing) { _, open in if trailing { listing = open } }
        #endif
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

struct PaneMenu: View {
    let panes: TabPanes
    let index: Int
    var newTab: ((Navigator, ColumnPrefs) -> Void)?

    var body: some View {
        // 칸 접기 from a segment, a strip, or the divider beside it (2026-11-08 사용자); on a strip, opening it again.
        if panes.folded.contains(index) {
            Button(.panesUnfold, systemImage: "arrow.left.and.line.vertical.and.arrow.right") { panes.press(index) }
        } else {
            Button(.panesCollapse, systemImage: "arrow.right.and.line.vertical.and.arrow.left") { panes.collapse(index) }
                .disabled(!panes.canCollapse(index))
        }
        Button(.panesClose, systemImage: "xmark") { panes.close(index) }
            .disabled(panes.count < 2)
        if let newTab {
            Button(.panesToTab, systemImage: "macwindow.badge.plus") {
                let navigator = panes.navigators[index]
                let columns = panes.columns[index]
                if panes.close(index) { newTab(navigator, columns) }
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

struct PlaceIcon: View {
    let place: Crumb
    /// In place of the course's color, for a mark that steps back (a tab segment out of focus).
    var tint: Color?

    var body: some View {
        if let dot = place.dot {
            CourseMark(icon: place.symbol, color: tint ?? dot)
        } else {
            LineIcon(symbol: place.symbol ?? "questionmark.folder").foregroundStyle(tint ?? Theme.Palette.chromeIcon)
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
    /// A rounded panel on the frame, on the Mac and the iPad alike; the iPhone's screen is the page itself, edge to edge
    /// (`barePanes`).
    func panePanel(ring: Color?) -> some View { modifier(PanePanel(ring: ring)) }
}

private struct PanePanel: ViewModifier {
    let ring: Color?
    @Environment(\.barePanes) private var bare

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: bare ? 0 : Theme.Radius.floating)
        content
            .background(Theme.Palette.page, in: shape)
            .clipShape(shape)
            .overlay { if !bare { shape.strokeBorder(Theme.Palette.lineSoft) } }
            // A hairline in the accent says which pane the toolbar and the keys act on, without dimming the others.
            .overlay { if let ring { shape.strokeBorder(ring, lineWidth: 1) } }
    }
}

extension EnvironmentValues {
    /// Panes drawn without their panel: the iPhone, whose screen is one page from edge to edge (#134).
    @Entry var barePanes = false
}

#if os(macOS)
import AppKit

/// Presses the pane it lies under when a click lands anywhere in it, or the divider on a double click. A local event
/// monitor, not a gesture: a note's text and preview page and a PDF take the click in AppKit before SwiftUI sees it.
/// It never takes the click itself.
struct PanePress: NSViewRepresentable {
    let active: Bool
    /// The click of a run that presses it: 2 for the second of a double click.
    var clicks = 1
    let press: @MainActor () -> Void

    func makeNSView(context: Context) -> Probe { Probe(press: press) }

    func updateNSView(_ view: Probe, context: Context) {
        view.active = active
        view.clicks = clicks
        view.press = press
    }

    final class Probe: NSView {
        var active = false
        var clicks = 1
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
            guard active, let window, event.window === window, !isHiddenOrHasHiddenAncestor, clicks == 1 || (event.type == .leftMouseDown && event.clickCount == clicks),
                  bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
            press()
        }
    }
}
#endif
