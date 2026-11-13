import FolioAI
import FolioDomain
import SwiftUI

struct PaneRow: View {
    let workspace: Workspace
    let panes: TabPanes
    let front: Bool
    let openLink: (Navigator) -> OpenLinkAction
    var play: (UUID, (@MainActor () -> Void)?) -> Void = { _, _ in }
    var newTab: ((Navigator, ColumnPrefs) -> Void)?
    @State private var sizes = PaneSizes()
    @State private var drag = PaneDrag()
    @GestureState private var dragging = false
    @State private var claude = false
    @State private var claudeAsk: ContextItem?
    @State private var inserts = PaneInserts()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let gap = Theme.Size.panelInset
    static let space = "panes"

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
        // 칸들을 만든 채로 넘겨야 drag가 stack만 다시 그린다. 여기서 비율을 읽으면 drag의 frame마다 이 body가 다시 실행되고,
        // 새로 넘기는 closure(`openLink`) 때문에 칸마다 화면도 다시 그려진다.
        LivePaneStack(panes: panes, drag: drag, fold: fold) {
            // 칸의 자리를 ID로 다시 찾는다. SwiftUI는 닫힌 칸의 뷰를 예전 자리로 한 번 더 실행할 수 있고, 그 자리는 칸 목록의 끝을
            // 넘는다(탭 막대의 segment에서도 그랬다).
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
        .overlay(alignment: .bottomTrailing) {
            WindowClaude(
                workspace: workspace, panes: panes, folded: folded, shown: $claude, incoming: $claudeAsk, inserts: inserts,
                openLink: openLink)
        }
        #if DEBUG && os(macOS)
        .onChange(of: SnapshotDriver.shared.claudePanel, initial: true) { _, new in claude = new }
        #endif
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width in
            sizes.row = width
            panes.measure(width)
        }
        .animation(reduceMotion ? nil : Theme.Motion.pane, value: panes.focus)
        .animation(reduceMotion ? nil : Theme.Motion.pane, value: panes.collapsed)
        .animation(reduceMotion ? nil : Theme.Motion.pane, value: panes.ids)
    }

    @ViewBuilder func pane(_ i: Int, id: UUID, look: PaneLayout.Fold.Look) -> some View {
        let folded = look != .open
        let navigator = panes.navigators[i]
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
                PaneBundle(
                    panes: panes,
                    held: held.map { j in
                        PaneBundle.Held(index: j, mark: workspace.paneMark(of: panes.navigators[j].current, trail: panes.trails[j]))
                    }, trailing: held.first.map { $0 > panes.focus } ?? false, newTab: newTab
                )
                .transition(.opacity)
            }
        }
        .panePanel(
            ring: panes.count > 1 && i == panes.focus
                ? navigator.current.course.map { workspace.accent($0).color } ?? Theme.Palette.chromeSelected : nil
        )
        .opacity(look == .hidden ? 0 : 1)
        .accessibilityHidden(look == .hidden)
        #if os(macOS)
        .background { PanePress(active: front && !folded) { panes.press(i) } }
        #else
        .simultaneousGesture(TapGesture().onEnded { panes.press(i) }, including: folded ? .subviews : .all)
        #endif
    }

    func strip(_ i: Int, byHand: Bool) -> some View {
        let navigator = panes.navigators[i]
        return PaneStrip(
            mark: workspace.paneMark(of: navigator.current, trail: panes.trails[i]), page: navigator.current.link.anchor?.pageNumber,
            byHand: byHand
        ) {
            panes.press(i)
        }
        .contextMenu { PaneMenu(panes: panes, index: i, newTab: newTab) }
        .transition(.opacity)
    }

    func divider(after d: Int, folded: Set<Int>, shown: Bool) -> some View {
        let enabled = !folded.contains(d) && !folded.contains(d + 1)
        return PaneDivider(enabled: enabled, front: front, even: panes.even)
            .allowsHitTesting(shown)
            #if os(macOS) && (DEBUG || RESIZE_PROBE)
        .background { if front && d == 0 { ResizeMarker(name: "divider") } }
            #endif
            .contextMenu {
                Button(.panesEven, systemImage: "rectangle.split.3x1", action: panes.even)
                Divider()
                ForEach([d, d + 1], id: \.self) { i in
                    Menu(workspace.paneMark(of: panes.navigators[i].current, trail: panes.trails[i]).title) {
                        PaneMenu(panes: panes, index: i, newTab: newTab)
                    }
                }
            }
            // 클릭할 때의 흔들림을 넘을 때부터 drag로 본다. 그래야 한두 point 움직인 두 번 클릭도 두 번 클릭이 된다. 위치가 아니라
            // 움직인 거리로 옮기므로, 여백을 잡았을 때 구분선이 포인터 위치로 건너뛰지 않는다.
            .gesture(
                DragGesture(minimumDistance: Self.wobble, coordinateSpace: .named(Self.space))
                    .updating($dragging) { _, dragging, _ in dragging = true }
                    .onChanged { drag in if enabled { dragged(d, by: drag.translation.width, folded: folded) } }
                    .onEnded { drag in
                        if enabled { dragged(d, by: drag.translation.width, folded: folded) }
                        dropped()
                    }
            )
            #if os(macOS) && (DEBUG || RESIZE_PROBE)
        .onAppear { if front && d == 0 { PaneDragHook.shared.row = self } }
        #endif
    }

    static let wobble: CGFloat = 4

    // drag가 끝날 때까지 폭은 `drag`에서만 그린다. 탭은 놓을 때 한 번만 폭을 받으므로, drag는 행 전체가 아니라 stack만
    // 배치하고 모든 화면의 closure를 새로 만들지 않는다.
    func dragged(_ d: Int, by translation: CGFloat, folded: Set<Int>) {
        if drag.from == nil {
            let widths = panes.layout.widths(
                room: sizes.row, fold: panes.fold, minWidth: Theme.Size.paneMin, strip: Theme.Size.paneStrip, gap: Self.gap)
            guard widths.indices.contains(d + 1) else { return }
            drag.from = PaneDrag.Start(divider: d, layout: panes.layout, left: widths[d], pair: widths[d] + widths[d + 1])
        }
        guard let from = drag.from, from.pair > 0 else { return }
        var live = from.layout
        live.resize(divider: d, to: (from.left + translation) / from.pair)
        if live != drag.live { drag.live = live }
    }

    // drag는 여기서 두 번 끝나므로, 두 번째 호출은 진행 중인 drag가 없어 아무것도 하지 않는다.
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
        var left: CGFloat
        var pair: CGFloat
    }

    @ObservationIgnored var from: Start?
    var live: PaneLayout?
}

#if os(macOS) && (DEBUG || RESIZE_PROBE)
// 합성한 mouse event는 실제 포인터가 움직일 때마다 drag를 잃는다. 그래서 `ResizeProbe`가 gesture와 같은 길로 구분선을
// 끈다.
@MainActor final class PaneDragHook {
    static let shared = PaneDragHook()
    var row: PaneRow?

    func move(by translation: CGFloat) { row.map { $0.dragged(0, by: translation, folded: $0.folded) } }

    func end() { row?.dropped() }
}
#endif

@MainActor final class PaneSizes {
    var open: [UUID: CGFloat] = [:]
    var row: CGFloat = 0
}

private struct LivePaneStack<Content: View>: View {
    let panes: TabPanes
    let drag: PaneDrag
    let fold: PaneLayout.Fold
    @ViewBuilder let content: Content

    var body: some View {
        let live = drag.live.flatMap { $0.panes.count == panes.count ? $0 : nil }
        let glide = live == nil ? panes.glide.flatMap { $0.from.panes.count == panes.count ? $0 : nil } : nil
        TimelineView(.animation(paused: glide == nil)) { context in
            PaneStack(
                layout: live ?? panes.layout, shares: live?.shares ?? panes.shares, fold: fold,
                from: glide.map { ($0.from, $0.fold) }, progress: glide?.progress(at: context.date) ?? 1
            ) { content }
        }
    }
}

private struct PaneStack: Layout {
    let layout: PaneLayout
    let shares: [Double]
    let fold: PaneLayout.Fold
    var from: (layout: PaneLayout, fold: PaneLayout.Fold)?
    var progress = 1.0

    static func sizes(_ layout: PaneLayout, _ fold: PaneLayout.Fold, room: CGFloat) -> (widths: [Double], gaps: [Double]) {
        let drawn = fold.count == layout.panes.count ? fold : layout.unfolded
        return (
            layout.widths(room: room, fold: drawn, minWidth: Theme.Size.paneMin, strip: Theme.Size.paneStrip, gap: PaneRow.gap),
            drawn.gaps(PaneRow.gap)
        )
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    // 행의 가장자리를 직접 정한다. 기본값에 맡기면 상위 view(ZStack)가 가장자리를 물을 때마다 모든 칸을 배치하고 그 화면을
    // 한 번 더 배치했다.
    func explicitAlignment(
        of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) -> CGFloat? { nil }

    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ())
        -> CGFloat?
    { nil }

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

// strip일 때는 열린 폭을 써서 접어도 다시 배치하지 않는다. glide로 열릴 때는 끝 폭을 써서 한 번만 배치하고, 패널의
// 가장자리가 그 위로 움직이게 한다. 그렇지 않으면 화면이 strip 폭에서 frame마다 넓어지며 다시 배치된다.
private struct PaneScreenWidth: ViewModifier {
    let panes: TabPanes
    let index: Int
    let kept: CGFloat?
    let sizes: PaneSizes

    func body(content: Content) -> some View {
        let width = kept ?? opening
        content.frame(width: width, alignment: .topLeading).animation(nil, value: width)
    }

    var opening: CGFloat? {
        guard let glide = panes.glide, glide.fold.folded.contains(index) else { return nil }
        guard !panes.folded.contains(index) else { return nil }
        let widths = panes.layout.widths(
            room: sizes.row, fold: panes.fold, minWidth: Theme.Size.paneMin, strip: Theme.Size.paneStrip, gap: PaneRow.gap)
        return widths.indices.contains(index) ? widths[index] : nil
    }
}

private struct PaneScreen: View {
    let workspace: Workspace
    let navigator: Navigator

    var body: some View { ScreenView(workspace: workspace, entry: navigator.current) }
}

private struct PaneDivider: View {
    let enabled: Bool
    let front: Bool
    let even: @MainActor () -> Void

    var body: some View {
        #if os(macOS)
        Color.clear
            .overlay {
                Color.clear.frame(width: Theme.Space.m).contentShape(.rect).pointerStyle(enabled ? .columnResize : nil)
                    // 칸의 누름처럼 tap gesture가 아니라 창의 event에서 받는다. 구분선의 drag 옆에서는 두 번째 클릭을 drag가 가져가기
                    // 때문이다.
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

private struct PaneStrip: View {
    let mark: Crumb
    let page: Int?
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

private struct PaneBundle: View {
    struct Held: Identifiable {
        let index: Int
        let mark: Crumb
        var id: Int { index }
    }

    let panes: TabPanes
    let held: [Held]
    let trailing: Bool
    var newTab: ((Navigator, ColumnPrefs) -> Void)?
    @State private var listing = false
    @State private var hovering = false

    private var listEdge: Edge {
        #if os(macOS)
        trailing ? .leading : .trailing
        #else
        trailing ? .trailing : .leading
        #endif
    }

    var body: some View {
        Button {
            listing = true
        } label: {
            VStack(spacing: Theme.Space.s) {
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
    func paneMark(of entry: Navigator.Entry, trail: CrumbTrail?) -> Crumb {
        let place = placeCrumb(of: entry)
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
            .overlay { if let ring { shape.strokeBorder(ring, lineWidth: 1) } }
    }
}

extension EnvironmentValues {
    @Entry var barePanes = false
}

#if os(macOS)
import AppKit

// gesture가 아니라 local event monitor를 쓴다. 노트의 글, 미리보기 페이지, PDF는 SwiftUI보다 먼저 AppKit에서 클릭을
// 받기 때문이다. 이 monitor는 클릭을 가져가지 않는다.
struct PanePress: NSViewRepresentable {
    let active: Bool
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
                // local monitor는 앱이 처리하는 event와 함께 main thread에서 실행된다.
                nonisolated(unsafe) let event = event
                MainActor.assumeIsolated { self?.check(event) }
                return event
            }
        }

        private func check(_ event: NSEvent) {
            guard active, let window, event.window === window, !isHiddenOrHasHiddenAncestor,
                clicks == 1 || (event.type == .leftMouseDown && event.clickCount == clicks),
                bounds.contains(convert(event.locationInWindow, from: nil))
            else { return }
            press()
        }
    }
}
#endif
