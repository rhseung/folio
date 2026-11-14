import FolioDomain
import SwiftUI

struct SectionBar: View {
    @Binding var split: LectureSplit
    @Binding var selected: Int?
    let label: (Int) -> String
    var page: Int?
    var pick: (Int) -> Void = { _ in }

    @Environment(\.accent) private var accent
    @State private var hovered: Int?
    @State private var hoverBoundary: Int?
    @State private var dragging: Int?
    @State private var moved = false
    @State private var ticks = 0
    @State private var bumps = 0

    static let tile: CGFloat = 28
    static let bubbleRow: CGFloat = 20
    private static let gap: CGFloat = 4
    #if os(macOS)
    private static let reach: CGFloat = 6
    #else
    private static let reach: CGFloat = Theme.Size.touchTarget / 2
    #endif

    var body: some View {
        GeometryReader { proxy in bar(width: proxy.size.width) }
            .frame(height: Self.bubbleRow + Self.tile)
            .sensoryFeedback(.selection, trigger: ticks)
            .sensoryFeedback(.alignment, trigger: bumps)
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(keys: [.leftArrow, .rightArrow], phases: [.down, .repeat]) { press in
                guard let i = selected, let reach = split.boundaryRange(after: i) else { return .ignored }
                let step = (press.key == .rightArrow ? 1 : -1) * (press.modifiers.contains(.shift) ? 5 : 1)
                let was = split.sections[i].lastPage
                let target = was + step
                let landed = split.moveBoundary(after: i, to: target)
                if !reach.contains(target) { bumps += 1 } else if landed != was { ticks += 1 }
                return .handled
            }
            .help(Text(.designSectionsBarHelp))
    }

    // MARK: Geometry

    private func x(_ edge: Int, _ w: CGFloat) -> CGFloat { CGFloat(edge) / CGFloat(split.pageCount) * w }
    private func page(at px: CGFloat, _ w: CGFloat) -> Int { min(max(Int(px / w * CGFloat(split.pageCount)) + 1, 1), split.pageCount) }

    private func rect(_ i: Int, _ w: CGFloat) -> CGRect {
        let s = split.sections[i]
        let lo = x(s.firstPage - 1, w) + (i == 0 ? 0 : Self.gap / 2)
        let hi = x(s.lastPage, w) - (i == split.sections.count - 1 ? 0 : Self.gap / 2)
        return CGRect(x: lo, y: Self.bubbleRow, width: max(hi - lo, 2), height: Self.tile)
    }

    private func boundary(near px: CGFloat, _ w: CGFloat) -> Int? {
        split.sections.indices.dropLast().min { abs(x(split.sections[$0].lastPage, w) - px) < abs(x(split.sections[$1].lastPage, w) - px) }
            .flatMap { abs(x(split.sections[$0].lastPage, w) - px) <= Self.reach ? $0 : nil }
    }

    private func shape(_ i: Int) -> UnevenRoundedRectangle {
        let first = i == 0, last = i == split.sections.count - 1
        let outer = Theme.Radius.control, inner = Theme.Radius.small
        return UnevenRoundedRectangle(
            topLeadingRadius: first ? outer : inner, bottomLeadingRadius: first ? outer : inner,
            bottomTrailingRadius: last ? outer : inner, topTrailingRadius: last ? outer : inner)
    }

    // MARK: Drawing

    private func bar(width w: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in draw(context, width: w) }
                .allowsHitTesting(false)
            ForEach(Array(split.sections.enumerated()), id: \.element.id) { i, s in
                let r = rect(i, w)
                Color.clear
                    .frame(width: r.width, height: r.height)
                    .overlay(alignment: .leading) { text(i, width: r.width) }
                    .contentShape(.rect)
                    .help(tip(i))
                    .position(x: r.midX, y: r.midY)
            }
            ForEach(grips, id: \.self) { b in
                Capsule()
                    .fill(dragging == b ? accent.color : Color.white)
                    .shadow(color: .black.opacity(0.28), radius: 1.5, y: 1)
                    .frame(width: 4, height: 16)
                    .position(x: x(split.sections[b].lastPage, w), y: Self.bubbleRow + Self.tile / 2)
                    .allowsHitTesting(false)
            }
            if let b = dragging, split.sections.indices.contains(b + 1) {
                let bx = x(split.sections[b].lastPage, w)
                Text(.designSectionsBoundary(split.sections[b].lastPage, split.sections[b + 1].firstPage))
                    .font(Theme.Typeface.label).monospacedDigit()
                    .padding(.horizontal, Theme.Space.s)
                    .frame(height: Self.bubbleRow - 2)
                    .background(Theme.Palette.card, in: .capsule)
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                    .fixedSize()
                    .position(x: min(max(bx, 32), w - 32), y: Self.bubbleRow / 2)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: w, height: Self.bubbleRow + Self.tile)
        .contentShape(.rect)
        .gesture(drag(width: w))
        .simultaneousGesture(
            SpatialTapGesture(count: 2).onEnded { v in
                if let made = split.split(at: page(at: v.location.x, w)) {
                    selected = made
                    bumps += 1
                }
            }
        )
        .onContinuousHover { phase in
            switch phase {
            case .active(let p):
                hoverBoundary = dragging == nil ? boundary(near: p.x, w) : hoverBoundary
                hovered = hoverBoundary == nil ? split.section(at: page(at: p.x, w)) : nil
            case .ended:
                hoverBoundary = nil
                hovered = nil
            }
        }
        #if os(macOS)
        .pointerStyle(hoverBoundary != nil || dragging != nil ? .columnResize : nil)
        #endif
        .animation(Theme.Motion.quick, value: split.sections.map(\.pages))
    }

    private func draw(_ context: GraphicsContext, width w: CGFloat) {
        for (i, s) in split.sections.enumerated() {
            let r = rect(i, w)
            let path = shape(i).path(in: r)
            if s.unit == nil {
                context.fill(path, with: .color(Theme.Palette.fill))
                var hatch = Path()
                var hx = r.minX - r.height
                while hx < r.maxX {
                    hatch.move(to: CGPoint(x: hx, y: r.maxY))
                    hatch.addLine(to: CGPoint(x: hx + r.height, y: r.minY))
                    hx += Theme.Space.s
                }
                var clipped = context
                clipped.clip(to: path)
                clipped.stroke(hatch, with: .color(Theme.Palette.text.opacity(Theme.Opacity.hover)), lineWidth: 1)
            } else {
                let opacity =
                    selected == i
                    ? Theme.Opacity.zonePicked
                    : hovered == i
                        ? Theme.Opacity.onTint
                        : i % 2 == 0 ? Theme.Opacity.tint : Theme.Opacity.zoneAlt
                context.fill(path, with: .color(accent.color.opacity(opacity)))
            }
            if s.isNew {
                context.stroke(
                    shape(i).inset(by: 0.5).path(in: r), with: .color(accent.color.opacity(Theme.Opacity.liveEdge)),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            } else if selected == i {
                context.stroke(
                    shape(i).inset(by: 0.5).path(in: r), with: .color(accent.color.opacity(Theme.Opacity.liveEdge)), lineWidth: 1)
            }
        }
        if let page, page >= 1, page <= split.pageCount {
            let px = x(page - 1, w) + x(1, w) / 2
            context.fill(Path(CGRect(x: px - 1, y: Self.bubbleRow + Self.tile - 4, width: 2, height: 4)), with: .color(Theme.Palette.text))
        }
    }

    @ViewBuilder private func text(_ i: Int, width: CGFloat) -> some View {
        let room = width - 2 * Theme.Space.s
        if room > 12, split.sections.indices.contains(i) {
            let s = split.sections[i]
            let name = label(i)
            let title = Text(name).font(Theme.Typeface.label).foregroundStyle(s.unit == nil ? Theme.Palette.textTertiary : accent.ink)
            let pages = Text(pagesText(s)).font(Theme.Typeface.label.weight(.regular)).foregroundStyle(Theme.Palette.textTertiary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Space.xs) {
                    title; pages
                }.fixedSize()
                if name.isEmpty { pages.fixedSize(); Color.clear } else { title.lineLimit(1).truncationMode(.tail) }
            }
            .frame(width: room, alignment: .leading)
            .clipped()
            .padding(.horizontal, Theme.Space.s)
            .allowsHitTesting(false)
        }
    }

    private var grips: [Int] {
        var out = Set([dragging ?? hoverBoundary].compactMap(\.self))
        #if os(iOS)
        if let selected { out.formUnion([selected - 1, selected]) }
        #endif
        return out.filter { split.sections.indices.contains($0) && split.sections.indices.contains($0 + 1) }.sorted()
    }

    private func pagesText(_ s: LectureSplit.Section) -> String {
        s.firstPage == s.lastPage ? "\(s.firstPage)" : "\(s.firstPage)–\(s.lastPage)"
    }

    private func tip(_ i: Int) -> String {
        let s = split.sections[i]
        let name = label(i).isEmpty ? String(localized: .designSectionsUnnamed) : label(i)
        return "\(name) · \(String(localized: .designSectionsPages(s.firstPage, s.lastPage)))"
    }

    // MARK: Changes

    private func drag(width w: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if dragging == nil, !moved { dragging = boundary(near: g.startLocation.x, w) }
                if abs(g.translation.width) > 2 { moved = true }
                guard let b = dragging, moved else { return }
                let target = Int((g.location.x / w * CGFloat(split.pageCount)).rounded())
                let was = split.sections[b].lastPage
                let landed = split.moveBoundary(after: b, to: target)
                if landed != was {
                    if landed != target { bumps += 1 } else { ticks += 1 }
                }
            }
            .onEnded { g in
                defer {
                    dragging = nil
                    moved = false
                }
                guard !moved else { return }
                let i = split.section(at: page(at: g.location.x, w))
                selected = i
                pick(split.sections[i].firstPage)
            }
    }
}
