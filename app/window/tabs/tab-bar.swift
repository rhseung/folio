import FolioDomain
import SwiftUI

struct TabBar: View {
    let tabs: WindowTabs
    let workspace: Workspace
    let crumbs: [Crumb]
    let toolbar: ToolbarRow
    let moveToWindow: (UUID) -> Void
    var nameLayout: (TabPanes) -> Void = { _ in }
    var manageLayouts: () -> Void = {}
    @State private var sizes = TabSizes()
    @State private var frames: [UUID: CGRect] = [:]
    @State private var dragged: (id: UUID, start: CGFloat)?
    @State private var dragOffset: CGFloat = 0
    @State private var stripOrigin: CGPoint = .zero
    @GestureState private var dragging = false

    static let gap = Theme.Space.s
    static let icon = Theme.Size.toolbarButton
    static let plus = "plus"
    // image의 폭이 아니라 실제로 칠한 폭을 쓴다. image 폭에는 기호의 side bearing이 양쪽 2point씩 들어 있어, +가 capsule
    // 사이의 간격보다 더 멀리 놓였다.
    static let plusInk = inkWidth(of: plus, size: Theme.Glyph.toolbarSize)

    static func inkWidth(of symbol: String, size: CGFloat) -> CGFloat {
        #if os(iOS)
        guard let image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: .regular)),
            let cg = image.cgImage
        else { return size }
        let width = cg.width, height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard
            let context = CGContext(
                data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return size }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        let inked = (0..<width).filter { x in (0..<height).contains { pixels[($0 * width + x) * 4 + 3] > 127 } }
        guard let first = inked.first, let last = inked.last else { return size }
        return CGFloat(last + 1 - first) / image.scale
        #else
        guard
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: size, weight: .regular))
        else { return size }
        let scale = 4
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(image.size.width) * scale,
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
        // 맞춤이나 앞 탭의 trail이 바뀔 때만 바뀌고, 창이 지나는 모든 폭마다 바뀌지는 않는다. live resize의 frame마다 탭을
        // 다시 그리는 비용은 frame이 감당하지 못한다(항목의 메뉴 형태를 매번 다시 만들던 AppKit 툴바에서는 창이 초당 몇
        // frame으로 떨어졌다).
        let placement = toolbar.placement
        let fit = placement.fit
        let shown = Array(others.prefix(fit.shown))
        let hidden = Array(others.dropFirst(fit.shown))
        let row = tabs.ids.filter { $0 == tabs.selected || shown.contains($0) }
        HStack(spacing: Self.gap) {
            ForEach(row, id: \.self) { id in
                Group {
                    if id == tabs.selected {
                        if let trail = placement.trail {
                            front(crumbRoom: trail, compact: fit.compactFront)
                                .frame(width: trail + CGFloat(toolbar.measures.front.chrome(compact: fit.compactFront)))
                        } else {
                            front(crumbRoom: .infinity, compact: fit.compactFront).fixedSize()
                        }
                    } else {
                        tab(id, form: TabForm(fit)).fixedSize()
                    }
                }
                #if os(macOS) && (DEBUG || RESIZE_PROBE)
                .background { if id == row.first { ResizeMarker(name: "firstTab") } }
                #endif
                .onGeometryChange(for: CGRect.self) {
                    $0.frame(in: .named(Self.space))
                } action: {
                    frames[id] = $0
                }
                #if DEBUG && os(macOS)
                .onGeometryChange(for: CGRect.self) {
                    $0.frame(in: .global)
                } action: {
                    if id == tabs.selected { LayoutSnapshots.selectedTab = $0 }
                }
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
        .onGeometryChange(for: CGPoint.self) {
            $0.frame(in: .global).origin
        } action: {
            stripOrigin = $0
        }
        .onChange(of: dragging) { _, now in if !now { tabs.drop = nil } }
        .background { measures(others) }
        .onChange(of: tabs.selected) { report() }
        .onChange(of: tabs.ids) { _, ids in
            let open = Set(ids)
            sizes.keep(open)
            report()
            frames = frames.filter { open.contains($0.key) }
        }
        .animation(Theme.Motion.standard, value: tabs.ids)
        .frame(width: placement.width, alignment: .leading)
        .padding(.leading, placement.lead)
    }

    static let space = "tabs"

    // 잰 값에서 바로 알린다. 재는 callback에서 설정한 state는 body에 늦게 닿거나 닿지 않았고, 줄이 앞 탭을 오래전 폭에 묶어
    // strip이 검색 칸 위로 넘어갔다.
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
                if tabs.count > 1 { closeButton(tabs.selected) }
            }
            .padding(.leading, Theme.Space.m)
            .padding(.trailing, tabs.count > 1 ? Theme.Space.xs : Theme.Space.m)
            .frame(height: Theme.Size.toolbarButton)
            .tabSurface(front: true)
        }
    }

    func joined(_ panes: TabPanes, crumbRoom: CGFloat, compact: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Segment.all(panes, workspace: workspace, playing: tabs.playingPanes)) { segment in
                if segment.index > 0 { SegmentRule() }
                TabSegment(
                    mark: segment.mark, crumbs: segment.index == panes.focus ? crumbs : nil, crumbRoom: crumbRoom, iconOnly: compact,
                    playing: segment.playing,
                    select: { panes.press(pane: segment.id) }, close: { panes.close(pane: segment.id) },
                    pause: { [tabs] in tabs.pause(pane: segment.id) }
                )
                .contextMenu {
                    if let i = panes.ids.firstIndex(of: segment.id) {
                        PaneMenu(panes: panes, index: i) { [tabs] navigator, columns in
                            tabs.open(navigator, columns: columns, fromLink: true)
                        }
                    }
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

    // 뷰 안에서 자리로 칸을 읽지 않는다. 칸이 닫힐 때 SwiftUI가 그 segment를 예전 자리로 한 번 더 실행했고, 그 자리가 칸
    // 목록의 끝을 넘어 앱이 비정상 종료되었다. 그래서 `ForEach`에 넘기기 전에 칸에서 읽는다.
    struct Segment: Identifiable {
        let id: UUID
        let index: Int
        let mark: Crumb
        let playing: Bool

        @MainActor static func all(_ panes: TabPanes, workspace: Workspace, playing: Set<UUID>) -> [Segment] {
            panes.ids.indices.map { i in
                Segment(
                    id: panes.ids[i], index: i, mark: workspace.paneMark(of: panes.navigators[i].current, trail: panes.trails[i]),
                    playing: playing.contains(panes.ids[i]))
            }
        }
    }

    func closeButton(_ id: UUID) -> some View {
        Button {
            tabs.close(id)
        } label: {
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
            label(id, form: form)
                .help(name)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(name)
        } else {
            let playing = tabs.playing.contains(id)
            Button {
                tabs.select(id)
            } label: {
                label(entry, title: form == .full ? title : nil, playing: playing)
            }
            .buttonStyle(.pointing(.plain))
            // 탭의 label 안에 둔 버튼은 탭을 고르므로, label이 남긴 자리 위에 별도의 버튼으로 둔다.
            .overlay(alignment: .trailing) { if playing && form == .full { speaker(id) } }
            .help(name)
            .accessibilityLabel(name)
        }
    }

    @ViewBuilder func label(_ id: UUID, form: TabForm) -> some View {
        if let panes = tabs.panes(id), panes.count > 1 {
            let segments = Segment.all(panes, workspace: workspace, playing: tabs.playingPanes)
            HStack(spacing: 0) {
                if form == .stacked {
                    Button {
                        tabs.select(id)
                    } label: {
                        HStack(spacing: Theme.Space.xxs) {
                            if segments.contains(where: \.playing) {
                                speakerIcon
                            } else if let first = segments.first {
                                PlaceIcon(place: first.mark)
                            }
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
                                Button {
                                    tabs.pause(pane: segment.id)
                                } label: {
                                    speakerIcon.contentShape(.rect)
                                }
                                .help(Text(.tabsPause))
                                .accessibilityLabel(Text(.tabsPause))
                            } else {
                                Button {
                                    tabs.select(id)
                                } label: {
                                    PlaceIcon(place: segment.mark).contentShape(.rect)
                                }
                                .accessibilityLabel(segment.mark.title)
                            }
                        }
                        .buttonStyle(.pointing(.plain))
                        .padding(.horizontal, Theme.Space.xs)
                    }
                    if form == .full, let preset = workspace.presetName(of: panes) {
                        Button {
                            tabs.select(id)
                        } label: {
                            CappedWidth(width: Theme.Size.tabName) { Text(preset).lineLimit(1) }
                        }
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
            .onTapGesture { tabs.select(id) }
        } else {
            let entry = tabs.navigator(id)?.current ?? Navigator.Entry(link: .place(.today))
            label(entry, title: form == .full ? workspace.tabTitle(of: entry) : nil, playing: tabs.playing.contains(id))
        }
    }

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
        Button {
            tabs.pause(id)
        } label: {
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
        // `.pointing(.plain)`이 아니라 plain을 쓴다. custom style은 메뉴를 pop-up button으로 되돌리고, 그 여백 때문에 capsule이
        // 잰 폭보다 넓게, 이웃과도 더 멀리 그려졌다.
        .buttonStyle(.plain)
        .pointingHand()
        .menuIndicator(.hidden)
        .fixedSize()
        .help(Text(.tabsMore(hidden.count)))
        .accessibilityLabel(Text(.tabsMore(hidden.count)))
    }

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

    func measures(_ others: [UUID]) -> some View {
        ZStack {
            Breadcrumb(crumbs: crumbs, foldWidth: .infinity, maxWidth: .infinity).fixedSize()
                .onGeometryChange(for: CGFloat.self, of: \.size.width) {
                    sizes.trail = $0; report()
                }
            front(crumbRoom: .infinity, compact: false).fixedSize()
                .onGeometryChange(for: CGFloat.self, of: \.size.width) {
                    sizes.front = $0; report()
                }
            front(crumbRoom: .infinity, compact: true).fixedSize()
                .onGeometryChange(for: CGFloat.self, of: \.size.width) {
                    sizes.compactFront = $0; report()
                }
            ForEach(others, id: \.self) { id in
                ForEach(TabForm.allCases, id: \.self) { form in
                    label(id, form: form).fixedSize()
                        .onGeometryChange(for: CGFloat.self, of: \.size.width) {
                            sizes.set($0, id, form); report()
                        }
                }
            }
            moreLabel(max(others.count, 10)).fixedSize()
                .onGeometryChange(for: CGFloat.self, of: \.size.width) {
                    sizes.more = $0; report()
                }
        }
        .hidden()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    func drag(_ id: UUID, row: [UUID]) -> some Gesture {
        DragGesture(minimumDistance: Theme.Space.xs, coordinateSpace: .named(Self.space))
            .updating($dragging) { _, state, _ in state = true }
            .onChanged { value in
                guard let frame = frames[id] else { return }
                if dragged?.id != id { dragged = (id, frame.minX) }
                let point = across(value.location)
                let drop = tabs.drop(for: id, at: point)
                if drop != tabs.drop { tabs.drop = drop }
                let content = tabs.contentFrame
                if content.isEmpty || point.y < content.minY { reorder(id, row: row, to: value.location.x) }
                dragOffset = value.translation.width - ((frames[id]?.minX ?? frame.minX) - (dragged?.start ?? frame.minX))
            }
            .onEnded { value in
                let drop = tabs.drop(for: id, at: across(value.location))
                tabs.drop = nil
                if let drop { tabs.merge(id, into: tabs.selected, at: drop.edge) }
                withAnimation(Theme.Motion.quick) {
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
        let index: Int =
            if before < others.count { rest.firstIndex(of: others[before]) ?? 0 } else {
                others.last.flatMap { rest.firstIndex(of: $0) }.map { $0 + 1 } ?? rest.count
            }
        rest.insert(id, at: index)
        if rest != tabs.ids { tabs.move(id, to: index) }
    }
}

private struct TabSegment: View {
    let mark: Crumb
    let crumbs: [Crumb]?
    let crumbRoom: CGFloat
    let iconOnly: Bool
    let playing: Bool
    let select: () -> Void
    let close: () -> Void
    let pause: () -> Void
    @State private var hovering = false

    static let height = Theme.Size.toolbarButton - Theme.Space.s
    static let close = Theme.Space.l

    var body: some View {
        HStack(spacing: Theme.Space.xxs) {
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

    var speakerButton: some View {
        Button(action: pause) {
            LineIcon(symbol: TabBar.speakerSymbol).contentShape(.rect)
        }
        .buttonStyle(.pointing(.plain))
        .help(Text(.tabsPause))
        .accessibilityLabel(Text(.tabsPause))
    }
}

private struct SegmentRule: View {
    var body: some View {
        Theme.Palette.text.opacity(Theme.Opacity.edge)
            .frame(width: 1, height: Theme.Space.l)
            .padding(.horizontal, Theme.Space.xxs)
    }
}

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
    func tabSurface(front: Bool) -> some View {
        background(Theme.Palette.text.opacity(front ? Theme.Opacity.tint : Theme.Opacity.wash), in: .capsule)
            .overlay { Capsule().strokeBorder(Theme.Palette.text.opacity(Theme.Opacity.edge)) }
    }
}
