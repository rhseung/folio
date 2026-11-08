import FolioDomain
import SwiftUI

/// A lecture file's pages as a thin bar, with one class's range on it in the course accent and one line under it that
/// reads the range. Pages other classes took lie faintly in the bar, and the pages seen while recording are a dotted
/// line under it to take in one tap. The numbers ride the handles only while one is dragged, pointed at or keyed:
/// at rest they would crowd the bar, and the line under it already says them. Every change goes through `PageRange`
/// (`moving`, `tapping`, `shifted`), so the range stays within the file and in order during a drag as much as after.
///
/// A lecture split into units (#321) draws its zones as tiles instead of the thin rail (the section bar, e2): the range
/// lies over them, the line reads it as the units it reaches, and its ends settle on zone edges unless ⌥ is held.
/// The tiles carry no names: a handle covered one wherever the range began or ended.
struct PageRangeField: View {
    /// Pages another class took through the file.
    struct Taught: Identifiable {
        let id: UUID
        let pages: ClosedRange<Int>
        let label: String
    }

    /// A zone of the file by the units holding it (#321); an empty title is pages no unit takes.
    struct Section: Equatable {
        let title: String
        let pages: ClosedRange<Int>
    }

    let range: PageRange
    /// The file's page count; nil while it isn't read yet.
    let pages: Int?
    var taught: [Taught] = []
    var seen: ClosedRange<Int>?
    var sections: [Section] = []
    /// What a range of a split file reads as (`CourseFile.sectionLabel`): `König–Hall`.
    var reads: ((ClosedRange<Int>) -> String?)?
    var compact = false
    /// Once a drag lets go, or at once for a tap, a key or a typed page: every step of a scrub would otherwise be a
    /// write.
    let set: (PageRange) -> Void

    @Environment(\.accent) private var accent
    @State private var draft: PageRange?
    @State private var grab: Grab?
    @State private var moved = false
    @State private var rubber: CGFloat = 0
    @State private var hovered: PageRange.End?
    @State private var hoverPage: Int?
    @State private var pushes: [PageRange.End: Int] = [:]
    @State private var typing: PageRange.End?
    @State private var typed: Int?
    @State private var ticks = 0
    @State private var bumps = 0
    /// A sheet hands its first control focus as it opens; the ring waits for a key so it marks only keyboard use.
    @State private var keyed = false
    /// The numbers over the handles, kept up a moment after the pointer leaves so it can reach them to type.
    @State private var pillsUp = false
    @State private var pillHover = false
    @FocusState private var focused: PageRange.End?
    @FocusState private var typingFocused: Bool

    private enum Grab: Equatable {
        case end(PageRange.End, from: PageRange)
        case span(from: PageRange, at: CGFloat)
    }

    /// Room left and right of the bar for a handle at either end.
    private static let inset: CGFloat = 12
    private static let bar: CGFloat = 8
    private static let pillRow: CGFloat = 24
    /// The bar's row, taller than the bar so it is easy to grab.
    private static let hitRow: CGFloat = 24
    /// The recording's dotted line under the bar, tall enough to press.
    private static let seenRow: CGFloat = 12
    /// Closer than this, the two pills would overlap and read as one: they merge.
    private static let mergeBelow: CGFloat = 56
    private static let grabReach: CGFloat = 10
    private static let spring = Animation.spring(duration: 0.32, bounce: 0.35)
    private static let zone: CGFloat = 12
    /// Within this much of a zone's edge, a dragged end settles on it.
    private static let snap: CGFloat = 0.75 // design: one-off, a fraction of a page, not a distance on screen

    private var zoned: Bool { !sections.isEmpty }
    /// The edges between zones, as page counts before them: where the ends settle and the firm haptic is.
    private var zoneEdges: Set<Int> { Set(sections.flatMap { [$0.pages.lowerBound - 1, $0.pages.upperBound] }) }

    private var shown: PageRange { draft ?? range }

    /// Pages the bar spans. Until the count is read, a little past what is known so the end can still be dragged on.
    private var extent: Int {
        if let pages { return max(pages, 1) }
        let ends: [Int?] = [shown.first, shown.last, seen?.upperBound]
        let known = (ends.compactMap { $0 } + taught.map(\.pages.upperBound) + sections.map(\.pages.upperBound)).max() ?? 0
        return max(known + 8, 24)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { proxy in track(width: proxy.size.width) }
                .frame(height: Self.pillRow + Self.hitRow)
            if let seen {
                GeometryReader { proxy in seenLine(seen, width: proxy.size.width) }
                    .frame(height: Self.seenRow)
            }
            if let readout {
                Text(readout)
                    .font(Theme.Typeface.caption)
                    .monospacedDigit()
                    // An end still to pick reads in the course ink: the row's cue, with no sentence for it.
                    .foregroundStyle(shown.lone == nil ? Theme.Palette.textSecondary : accent.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, Self.inset)
                    .padding(.top, Theme.Space.s)
            }
        }
        .frame(minWidth: compact ? 200 : 240)
        .onChange(of: wantsPills) { _, want in
            if want { pillsUp = true; return }
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                if !wantsPills { pillsUp = false }
            }
        }
        .sensoryFeedback(.selection, trigger: ticks)
        // Firmer where the drag stops giving or starts pushing: the file's first or last page, or the other end.
        .sensoryFeedback(.alignment, trigger: bumps)
    }

    // MARK: Geometry

    private func unit(_ w: CGFloat) -> CGFloat { max(w - 2 * Self.inset, 1) / CGFloat(extent) }
    /// Where the edge after `pages` pages sits: the start's handle is at its page's left edge, the end's at its right.
    private func x(_ edge: Int, _ w: CGFloat) -> CGFloat { Self.inset + CGFloat(edge) * unit(w) }
    private func edge(at x: CGFloat, _ w: CGFloat) -> CGFloat { (x - Self.inset) / unit(w) }
    private func page(at x: CGFloat, _ w: CGFloat) -> Int { min(max(Int(edge(at: x, w).rounded(.down)) + 1, 1), extent) }
    private var barY: CGFloat { Self.pillRow + Self.hitRow / 2 }

    private func handleX(_ end: PageRange.End, _ r: PageRange, _ w: CGFloat) -> CGFloat? {
        end == .first ? r.first.map { x($0 - 1, w) } : r.last.map { x($0, w) }
    }

    private func nearHandle(_ px: CGFloat, _ r: PageRange, _ w: CGFloat) -> PageRange.End? {
        let a = handleX(.first, r, w).map { abs($0 - px) } ?? .infinity
        let b = handleX(.last, r, w).map { abs($0 - px) } ?? .infinity
        guard min(a, b) <= Self.grabReach else { return nil }
        if a == b, let xa = handleX(.first, r, w) { return px < xa ? .first : .last }
        return a < b ? .first : .last
    }

    // MARK: Track

    private func track(width w: CGFloat) -> some View {
        let r = shown
        let xa = handleX(.first, r, w), xb = handleX(.last, r, w)
        return ZStack(alignment: .topLeading) {
            Canvas { context, _ in rail(context, width: w) }
                .allowsHitTesting(false)
            if zoned, let xa, let xb {
                RoundedRectangle(cornerRadius: Theme.Radius.tile)
                    .fill(accent.color.opacity(Theme.Opacity.onTint))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.tile).strokeBorder(accent.color, lineWidth: 1.5))
                    .frame(width: max(xb - xa, Self.bar), height: Self.zone + 4)
                    .offset(x: grabbedSpan ? rubber : 0)
                    .position(x: (xa + xb) / 2, y: barY)
                    .allowsHitTesting(false)
            } else if let xa, let xb {
                Capsule()
                    .fill(LinearGradient(colors: [accent.color.opacity(0.8), accent.color], startPoint: .top, endPoint: .bottom))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5))
                    .shadow(color: accent.color.opacity(0.4), radius: 2, y: 1)
                    .frame(width: max(xb - xa, Self.bar), height: Self.bar)
                    .offset(x: grabbedSpan ? rubber : 0)
                    .position(x: (xa + xb) / 2, y: barY)
                    .allowsHitTesting(false)
            }
            if let xa { handle(.first, x: xa) }
            if let xb { handle(.last, x: xb) }
            pills(r, xa: xa, xb: xb, width: w)
            Color.clear
                .contentShape(.rect)
                .frame(width: w, height: Self.hitRow)
                .position(x: w / 2, y: barY)
                .gesture(drag(width: w))
                .onContinuousHover { phase in
                    switch phase {
                    case let .active(p):
                        hovered = grab == nil ? nearHandle(p.x, shown, w) : hovered
                        hoverPage = grab == nil && hovered == nil ? page(at: p.x, w) : nil
                    case .ended:
                        hovered = nil
                        hoverPage = nil
                    }
                }
                #if os(macOS)
                .pointerStyle(hovered != nil || grab != nil ? .columnResize : nil)
                #endif
                .accessibilityHidden(true)
            if let p = hoverPage, !pillsUp { tip(p, width: w) }
        }
        .frame(width: w, height: Self.pillRow + Self.hitRow)
    }

    private func rail(_ context: GraphicsContext, width w: CGFloat) {
        if zoned { return zones(context, width: w) }
        let n = extent, u = unit(w), top = barY - Self.bar / 2
        context.fill(Capsule().path(in: CGRect(x: Self.inset, y: top, width: w - 2 * Self.inset, height: Self.bar)),
                     with: .color(Theme.Palette.fill))
        // A 1pt gap on each side, so two classes that meet still read as two.
        for t in taught where t.pages.lowerBound <= n {
            let upper = min(t.pages.upperBound, n)
            let rect = CGRect(x: x(t.pages.lowerBound - 1, w) + 1, y: top, width: max(CGFloat(upper - t.pages.lowerBound + 1) * u - 2, 1), height: Self.bar)
            context.fill(Capsule().path(in: rect), with: .color(Theme.Palette.text.opacity(Theme.Opacity.projected)))
        }
        let strong = Set(sections.flatMap { [$0.pages.lowerBound - 1, $0.pages.upperBound] })
        // Page ticks only while there is room for them; every fifth and every section edge always.
        let everyPage = u >= 4
        for i in 1..<n where everyPage || i % 5 == 0 || strong.contains(i) {
            let major = i % 5 == 0 || strong.contains(i)
            let h = major ? Self.bar : Self.bar / 2
            context.fill(Path(CGRect(x: x(i, w) - 0.5, y: barY - h / 2, width: 1, height: h)),
                         with: .color(Theme.Palette.text.opacity(major ? Theme.Opacity.toneEdge : Theme.Opacity.hover)))
        }
    }

    /// The zones as grey tiles; pages other classes took darken them, as they do the plain rail.
    private func zones(_ context: GraphicsContext, width w: CGFloat) {
        let n = extent, top = barY - Self.zone / 2
        for (i, s) in sections.enumerated() where s.pages.lowerBound <= n {
            let lo = x(s.pages.lowerBound - 1, w) + (i == 0 ? 0 : 2), hi = x(min(s.pages.upperBound, n), w) - (i == sections.count - 1 ? 0 : 2)
            let rect = CGRect(x: lo, y: top, width: max(hi - lo, 1), height: Self.zone)
            context.fill(Path(roundedRect: rect, cornerRadius: Theme.Radius.tile), with: .color(Theme.Palette.fill))
        }
        // Until the count is read the bar runs past the last zone, so an end can still be dragged on: those pages are
        // a zone no unit takes.
        if let last = sections.last?.pages.upperBound, last < n {
            let rect = CGRect(x: x(last, w) + 2, y: top, width: max(x(n, w) - x(last, w) - 2, 1), height: Self.zone)
            context.fill(Path(roundedRect: rect, cornerRadius: Theme.Radius.tile), with: .color(Theme.Palette.fill))
        }
        for t in taught where t.pages.lowerBound <= n {
            let upper = min(t.pages.upperBound, n)
            let rect = CGRect(x: x(t.pages.lowerBound - 1, w) + 1, y: top, width: max(x(upper, w) - x(t.pages.lowerBound - 1, w) - 2, 1), height: Self.zone)
            context.fill(Path(roundedRect: rect, cornerRadius: Theme.Radius.tile), with: .color(Theme.Palette.text.opacity(Theme.Opacity.projected)))
        }
    }

    /// The range in one line: `Hall의 정리–증가 경로 · 14–20쪽`, `14–20쪽` off units, `7쪽부터` with an end to pick.
    private var readout: String? {
        switch (shown.first, shown.last) {
        case let (f?, l?):
            let pages = String(localized: f == l ? .designPageRangeLength(f) : .designPageRangeSpan(f, l))
            guard let name = reads?(f...l) else { return pages }
            return String(localized: .designPageRangeSummary(name, pages))
        case let (f?, nil): return String(localized: .designPageRangeFromPage(f))
        case let (nil, l?): return String(localized: .designPageRangeToPage(l))
        default: return nil
        }
    }

    private var wantsPills: Bool { grab != nil || typing != nil || hovered != nil || pillHover || (keyed && focused != nil) }

    private var grabbedEnd: PageRange.End? { if case let .end(end, _) = grab { end } else { nil } }
    private var grabbedSpan: Bool { if case .span = grab { true } else { false } }

    private func handle(_ end: PageRange.End, x hx: CGFloat) -> some View {
        let scale: CGFloat = grabbedEnd == end ? 1.3 : hovered == end ? 1.15 : 1
        let value = shown[end]
        return Capsule()
            .fill(Color.white)
            .overlay(Capsule().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.28), radius: 1.5, y: 1)
            .frame(width: 12, height: 22)
            .overlay {
                if keyed, focused == end { Capsule().inset(by: -3).stroke(accent.color.opacity(0.45), lineWidth: 3) }
            }
            .scaleEffect(scale)
            .animation(Self.spring, value: scale)
            .keyframeAnimator(initialValue: 1.0, trigger: pushes[end, default: 0]) { view, s in
                view.scaleEffect(s)
            } keyframes: { _ in
                KeyframeTrack(\.self) {
                    SpringKeyframe(1.45, duration: 0.12)
                    SpringKeyframe(1, duration: 0.26)
                }
            }
            .offset(x: grabbedEnd == end || grabbedSpan ? rubber : 0)
            .position(x: hx, y: barY)
            .focusable()
            .focusEffectDisabled()
            .focused($focused, equals: end)
            .onKeyPress(keys: [.leftArrow, .rightArrow], phases: [.down, .repeat]) { press in
                keyed = true
                let step = (press.key == .rightArrow ? 1 : -1) * (press.modifiers.contains(.shift) ? 5 : 1)
                nudge(end, by: step)
                return .handled
            }
            .accessibilityElement()
            .accessibilityLabel(Text(end == .first ? .designPageRangeFirst : .designPageRangeLast))
            .accessibilityValue(value.map(String.init) ?? "")
            .accessibilityAdjustableAction { direction in nudge(end, by: direction == .increment ? 1 : -1) }
    }

    // MARK: Pills

    @ViewBuilder
    private func pills(_ r: PageRange, xa: CGFloat?, xb: CGFloat?, width w: CGFloat) -> some View {
        let y = Self.pillRow / 2
        let clamp = { (x: CGFloat, half: CGFloat) in min(max(x, half), w - half) }
        switch (r.first, r.last, xa, xb) {
        case let (f?, l?, xa?, xb?):
            let merged = moved || xb - xa < Self.mergeBelow
            pill {
                number(.first, f)
                if f != l {
                    Text("–").foregroundStyle(Theme.Palette.textTertiary)
                    number(.last, l)
                }
                Text(.designPageRangeUnit).foregroundStyle(Theme.Palette.textSecondary)
                if moved {
                    Text("·").foregroundStyle(Theme.Palette.textTertiary).padding(.horizontal, Theme.Space.xs)
                    Text(.designPageRangeLength(l - f + 1)).foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            .position(x: clamp((xa + xb) / 2, 40), y: y)
            .opacity(pillsUp && merged ? 1 : 0)
            .allowsHitTesting(pillsUp && merged)
            pill { number(.first, f) }
                .position(x: clamp(xa, 16), y: y)
                .opacity(pillsUp && !merged ? 1 : 0)
                .allowsHitTesting(pillsUp && !merged)
            pill { number(.last, l) }
                .position(x: clamp(xb, 16), y: y)
                .opacity(pillsUp && !merged ? 1 : 0)
                .allowsHitTesting(pillsUp && !merged)
        case let (f?, nil, xa?, _):
            pill { number(.first, f) }
                .position(x: clamp(xa, 16), y: y)
                .opacity(pillsUp ? 1 : 0)
                .allowsHitTesting(pillsUp)
        case let (nil, l?, _, xb?):
            pill { number(.last, l) }
                .position(x: clamp(xb, 16), y: y)
                .opacity(pillsUp ? 1 : 0)
                .allowsHitTesting(pillsUp)
        default:
            EmptyView()
        }
    }

    private func pill<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 0) { content() }
            .font(Theme.Typeface.label)
            .monospacedDigit()
            .padding(.horizontal, Theme.Space.s)
            .frame(height: 22)
            .background(Theme.Palette.card, in: .capsule)
            .overlay(Capsule().strokeBorder(Theme.Palette.lineStrong, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
            .fixedSize()
            .onHover { pillHover = $0 }
            .animation(.easeOut(duration: 0.18), value: moved)
            .animation(.easeOut(duration: 0.15), value: pillsUp)
    }

    @ViewBuilder
    private func number(_ end: PageRange.End, _ value: Int) -> some View {
        if typing == end {
            TextField(value: $typed, format: .number.grouping(.never)) { EmptyView() }
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .frame(width: 32)
                .focused($typingFocused)
                .onSubmit { commitTyped() }
                .onKeyPress(.escape) { typing = nil; typed = nil; return .handled }
                .onChange(of: typingFocused) { _, now in if !now { commitTyped() } }
                .onAppear { typingFocused = true }
        } else {
            Text(String(value))
                .padding(.horizontal, Theme.Space.xxs)
                .contentShape(.rect)
                .onTapGesture {
                    // Both numbers share one focus, so leaving the other one for this never blurs it: what was typed
                    // there is kept here or it's lost. Its push may move this end, hence the committed range's value.
                    let now = commitTyped()
                    typed = now[end] ?? value
                    typing = end
                }
                .help(Text(.designDragOrTypeHelp))
        }
    }

    private func tip(_ p: Int, width w: CGFloat) -> some View {
        let label = taught.first { $0.pages.contains(p) }?.label
        let zone = sections.first { $0.pages.contains(p) && !$0.title.isEmpty }?.title
        return Group {
            if let zone { Text(.designPageRangeTipSection(p, zone)) }
            else if let label { Text(.designPageRangeTipTaught(p, label)) } else { Text(.designPageRangeLength(p)) }
        }
        .font(Theme.Typeface.caption)
        .padding(.horizontal, Theme.Space.s)
        .padding(.vertical, Theme.Space.xxs)
        .background(Theme.Palette.card, in: .capsule)
        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        .fixedSize()
        .position(x: x(p - 1, w) + unit(w) / 2, y: Self.pillRow / 2)
        .allowsHitTesting(false)
    }

    // MARK: Below the bar

    /// The pages seen while recording as a dotted line under them; pressing it takes them as the range. A line rather
    /// than a labelled box: the box and its words sat against the bar and the readout, and the tooltip says the rest.
    private func seenLine(_ seen: ClosedRange<Int>, width w: CGFloat) -> some View {
        let lo = x(seen.lowerBound - 1, w), hi = x(min(seen.upperBound, extent), w)
        let applied = shown.first == seen.lowerBound && shown.last == seen.upperBound
        return Button {
            apply(PageRange().moving(.first, to: seen.lowerBound, pages: pages).moving(.last, to: seen.upperBound, pages: pages))
        } label: {
            Path { path in
                path.move(to: CGPoint(x: 0, y: Self.seenRow / 2))
                path.addLine(to: CGPoint(x: max(hi - lo, 1), y: Self.seenRow / 2))
            }
            .stroke(accent.color.opacity(applied ? 1 : 0.7), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: applied ? [] : [2, 4]))
            .frame(width: max(hi - lo, 1), height: Self.seenRow)
            .contentShape(.rect)
        }
        .buttonStyle(.pointing(.plain))
        .help(Text(.designPageRangeSeenHelp))
        .accessibilityLabel(Text(.designPageRangeSeenShort(seen.lowerBound, seen.upperBound)))
        .position(x: (lo + hi) / 2, y: Self.seenRow / 2)
    }

    // MARK: Changes

    private func drag(width w: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if grab == nil { begin(at: g.startLocation.x, width: w) }
                if !moved, abs(g.translation.width) > 2 { moved = true }
                guard moved else { return }
                let u = unit(w)
                switch grab {
                case let .end(end, from):
                    let e = edge(at: g.location.x, w)
                    let settled = settle(e)
                    let p = end == .first ? Int(settled.rounded()) + 1 : Int(settled.rounded())
                    // The only handle on the bar opens the range toward the pointer, as a tap there would: it is the
                    // one thing in sight to grab, and moving it instead left the missing end unset.
                    let next = from.lone == end ? from.tapping(page(at: g.location.x, w), pages: pages)
                        : from.moving(end, to: min(max(p, 1), extent), pages: pages)
                    change(to: next, end: end)
                    // Past the file's first or last page the handle gives a little, less the further it goes.
                    let (lo, hi): (CGFloat, CGFloat) = end == .first ? (0, CGFloat(extent - 1)) : (1, CGFloat(extent))
                    rubber = stretch((e < lo ? e - lo : e > hi ? e - hi : 0) * u)
                case let .span(from, at):
                    guard let f = from.first, let l = from.last else { return }
                    let raw = CGFloat(f) + (g.location.x - at) / u
                    change(to: from.shifted(by: Int((raw - CGFloat(f)).rounded()), pages: pages ?? extent), end: nil)
                    let hi = CGFloat(extent - (l - f))
                    rubber = stretch((raw < 1 ? raw - 1 : raw > hi ? raw - hi : 0) * u)
                case nil:
                    break
                }
            }
            .onEnded { _ in
                if let draft, draft != range { set(draft) }
                withAnimation(Self.spring) { rubber = 0 }
                draft = nil
                grab = nil
                moved = false
            }
    }

    /// A dragged end near a zone edge lands on it, unless ⌥ asks for single pages. iPad has no ⌥ to hold, so it always
    /// settles: the typed number is there for a page off an edge.
    private func settle(_ e: CGFloat) -> CGFloat {
        guard zoned else { return e }
        #if os(macOS)
        if NSEvent.modifierFlags.contains(.option) { return e }
        #endif
        guard let near = zoneEdges.min(by: { abs(CGFloat($0) - e) < abs(CGFloat($1) - e) }), abs(CGFloat(near) - e) <= Self.snap else { return e }
        return CGFloat(near)
    }

    /// A press on a handle takes that end, on the range the whole of it; anywhere else on the bar is a tap there,
    /// whose moved end the drag then carries on.
    private func begin(at px: CGFloat, width w: CGFloat) {
        let r = shown
        if let end = nearHandle(px, r, w) {
            grab = .end(end, from: r)
            focused = end
        } else if let f = r.first, let l = r.last, px > x(f - 1, w), px < x(l, w) {
            grab = .span(from: r, at: px)
        } else {
            let p = page(at: px, w)
            let next = r.tapping(p, pages: pages)
            // The end that landed on the tapped page; a first tap sets both, and the drag goes on with the end.
            let end: PageRange.End = next.last == p ? .last : .first
            withAnimation(Self.spring) { draft = next }
            feel(from: r, to: next, end: end)
            grab = .end(end, from: next)
            focused = end
        }
        hoverPage = nil
    }

    private func change(to next: PageRange, end: PageRange.End?) {
        let was = shown
        guard next != was else { return }
        draft = next
        feel(from: was, to: next, end: end)
    }

    private func feel(from was: PageRange, to next: PageRange, end: PageRange.End?) {
        guard next != was else { return }
        let firm: Bool
        if let end {
            let other: PageRange.End = end == .first ? .last : .first
            let pushed = was[other] != nil && was[other] != next[other]
            if pushed { pushes[other, default: 0] += 1 }
            let edgeOf = { (r: PageRange) in r[end].map { end == .first ? $0 - 1 : $0 } }
            let onZoneEdge = zoned && edgeOf(next).map(zoneEdges.contains) == true && edgeOf(was) != edgeOf(next)
            firm = pushed || onZoneEdge || (next.touches(end, pages: pages) && !was.touches(end, pages: pages) && next[end] != next[other])
        } else {
            firm = next.first == 1 || (pages != nil && next.last == pages)
        }
        if firm { bumps += 1 } else { ticks += 1 }
    }

    private func stretch(_ over: CGFloat) -> CGFloat {
        over == 0 ? 0 : (over < 0 ? -1 : 1) * 12 * (1 - exp(-abs(over) / 40))
    }

    private func apply(_ next: PageRange) {
        guard next != range else { return }
        feel(from: range, to: next, end: nil)
        withAnimation(Self.spring) { set(next) }
    }

    private func nudge(_ end: PageRange.End, by step: Int) {
        guard let value = range[end] else { return }
        let next = range.lone == end ? range.tapping(value + step, pages: pages) : range.moving(end, to: value + step, pages: pages)
        guard next != range else {
            // At the file's edge: the handle leans out and springs back.
            bumps += 1
            withAnimation(.easeOut(duration: 0.08)) { rubber = step > 0 ? 4 : -4; grab = .end(end, from: range) }
            withAnimation(Self.spring.delay(0.08)) { rubber = 0 } completion: { grab = nil }
            return
        }
        feel(from: range, to: next, end: end)
        withAnimation(Self.spring) { set(next) }
    }

    @discardableResult private func commitTyped() -> PageRange {
        guard let end = typing else { return range }
        typing = nil
        defer { typed = nil }
        guard let typed else { return range }
        let next = range.moving(end, to: typed, pages: pages)
        guard next != range else { return range }
        feel(from: range, to: next, end: end)
        withAnimation(Self.spring) { set(next) }
        return next
    }
}

extension PageRangeField.Taught {
    /// Every other class's pages through `material`, named by its day.
    static func list(_ file: CourseFile, material: UUID, besides session: UUID, calendar: Calendar) -> [Self] {
        file.pagesTaught(in: material, besides: session).map { Self(id: $0.session.id, pages: $0.pages, label: file.day(of: $0.session, calendar: calendar)) }
    }
}
