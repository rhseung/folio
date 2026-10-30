import FolioDomain
import SwiftUI

/// A scrolling page: cards on a quiet background, centered at reading width.
struct Page<Content: View, Backdrop: View>: View {
    var maxWidth: CGFloat = Theme.Size.pageMaxWidth
    // Behind the content's top across the page's full width, scrolling away with it: Today's course wash.
    @ViewBuilder var backdrop: Backdrop
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.section) { content }
                .frame(maxWidth: maxWidth, alignment: .leading)
                .padding(.horizontal, Theme.Space.xxl)
                .padding(.top, Theme.Space.xl)
                .padding(.bottom, Theme.Space.xxl * 2)
                .frame(maxWidth: .infinity)
                .background(alignment: .top) { backdrop }
        }
        .background(Theme.Palette.page)
        // No edge effect under the toolbar: on this flat paper it reads as a header band with a rule across the page.
        .scrollEdgeEffectHidden(true, for: .top)
        .foregroundStyle(Theme.Palette.text)
        .font(Theme.Typeface.body)
    }
}

extension Page where Backdrop == EmptyView {
    init(maxWidth: CGFloat = Theme.Size.pageMaxWidth, @ViewBuilder content: () -> Content) {
        self.init(maxWidth: maxWidth, backdrop: { EmptyView() }, content: content)
    }
}

/// Page heading: optional chips above, title, and a muted line below.
struct PageHeader<Chips: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var chips: Chips

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.tight) { chips }
            Text(title).font(Theme.Typeface.pageTitle)
            if let subtitle { Text(subtitle).foregroundStyle(Theme.Palette.textTertiary) }
        }
    }
}

extension PageHeader where Chips == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// The rule between a list column and its page. It runs up under the bandless toolbar with the column's background;
/// one that stopped at the safe area left the border missing beside the column's top.
struct ColumnDivider: View {
    var body: some View { Theme.Palette.line.frame(width: 1).ignoresSafeArea() }
}

/// One step of the window's breadcrumb. A step with an action goes back to it; the last step is where the window is.
struct Crumb {
    var title: String
    var symbol: String?
    var dot: Color?
    var action: (() -> Void)?
}

/// The steps pages below the window's own add to its breadcrumb: 1 a course's section, 2 what the section opened.
/// One trail drawn by the window, not a toolbar item per page, so a long one can fold its middle away.
@MainActor @Observable final class CrumbTrail {
    private var levels: [Int: (owner: UUID, crumb: Crumb)] = [:]
    var crumbs: [Crumb] { levels.keys.sorted().compactMap { levels[$0]?.crumb } }

    func set(_ crumb: Crumb, level: Int, owner: UUID) { levels[level] = (owner, crumb) }
    /// Only the owner's own step: switching pages shows the new one before the old one has gone.
    func clear(level: Int, owner: UUID) { if levels[level]?.owner == owner { levels[level] = nil } }
}

extension View {
    /// Adds this page to the window's breadcrumb while it is on screen. There is no back button: the steps before go back.
    func crumb(_ title: String, level: Int, symbol: String? = nil, action: (() -> Void)? = nil) -> some View {
        modifier(CrumbStep(title: title, level: level, symbol: symbol, action: action))
    }
}

private struct CrumbStep: ViewModifier {
    let title: String
    let level: Int
    let symbol: String?
    let action: (() -> Void)?
    @Environment(CrumbTrail.self) private var trail: CrumbTrail?
    @State private var owner = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear(perform: register)
            .onChange(of: title) { register() }
            .onChange(of: symbol) { register() }
            .onDisappear { trail?.clear(level: level, owner: owner) }
    }

    func register() { trail?.set(Crumb(title: title, symbol: symbol, action: action), level: level, owner: owner) }
}

/// The window's breadcrumb. Longer than `foldWidth`, it keeps the first and last steps and folds the middle into "…",
/// which lists them in a popover: a growing trail pushed the centered search field aside. Folded, it truncates only
/// past `maxWidth`, so a narrow window doesn't also cut the names it kept.
struct Breadcrumb: View {
    let crumbs: [Crumb]
    let foldWidth: CGFloat
    let maxWidth: CGFloat
    @State private var fullWidth: CGFloat = 0
    @State private var showsHidden = false

    var body: some View {
        let folded = crumbs.count > 2 && fullWidth > foldWidth
        HStack(spacing: Theme.Space.s) {
            if folded, let first = crumbs.first, let last = crumbs.last {
                step(first, at: 0)
                separator
                Button(.designHiddenPath, systemImage: "ellipsis") { showsHidden = true }
                    .buttonStyle(.toolbar)
                    .help(Text(.designHiddenPath))
                    .popover(isPresented: $showsHidden, arrowEdge: .bottom) { hidden }
                separator
                step(last, at: crumbs.count - 1)
            } else {
                row
            }
        }
        .lineLimit(1)
        .frame(maxWidth: maxWidth, alignment: .leading)
        .background {
            row.fixedSize().hidden().onGeometryChange(for: CGFloat.self, of: \.size.width) { fullWidth = $0 }
        }
    }

    var row: some View {
        HStack(spacing: Theme.Space.s) {
            ForEach(crumbs.indices, id: \.self) { i in
                if i > 0 { separator }
                step(crumbs[i], at: i)
            }
        }
    }

    var separator: some View { Text("/").font(Theme.Typeface.bodyStrong).foregroundStyle(Theme.Palette.textTertiary) }

    /// The first step carries the page's icon; the steps between are quieter links back.
    @ViewBuilder func step(_ crumb: Crumb, at i: Int) -> some View {
        let between = i > 0 && i < crumbs.count - 1
        HStack(spacing: Theme.Space.s) {
            if i == 0 {
                if let dot = crumb.dot {
                    CourseMark(icon: crumb.symbol, color: dot)
                } else if let symbol = crumb.symbol {
                    LineIcon(symbol: symbol).foregroundStyle(Theme.Palette.chromeIcon)
                }
            }
            if between, let action = crumb.action {
                Button(crumb.title, action: action).buttonStyle(.pointing(.plain)).help(Text(.designCrumbTopHelp(crumb.title)))
            } else {
                Text(crumb.title)
            }
        }
        .font(between ? Theme.Typeface.body : Theme.Typeface.bodyStrong)
        .foregroundStyle(between ? Theme.Palette.textSecondary : Theme.Palette.text)
    }

    var hidden: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            ForEach(Array(crumbs.dropFirst().dropLast().enumerated()), id: \.offset) { _, crumb in
                Button {
                    showsHidden = false
                    crumb.action?()
                } label: {
                    ColumnRow(title: crumb.title, symbol: crumb.symbol ?? "folder", chosen: false)
                }
                .buttonStyle(.pointing(.plain))
                .disabled(crumb.action == nil)
            }
        }
        .padding(Theme.Space.s)
        .frame(minWidth: 200)
        .font(Theme.Typeface.body)
    }
}

/// A page's own tools (a note's view mode, a PDF's zoom) in a slim row along the top of its pane, ruled off from
/// the content. Not in the window toolbar: there they ran into the breadcrumb.
struct PageBar<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Space.xxs) {
                leading
                Spacer(minLength: Theme.Space.s)
                trailing
            }
            .buttonStyle(.toolbar)
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, Theme.Space.xs)
            Theme.Palette.lineSoft.frame(height: 1)
        }
    }
}

/// A titled group: muted heading above the content, with an optional trailing action.
struct Block<Content: View, Trailing: View>: View {
    let title: String
    var note: String?
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Text(title).font(Theme.Typeface.sectionTitle).foregroundStyle(Theme.Palette.textSecondary)
                if let note { Text(note).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary) }
                Spacer(minLength: 0)
                trailing.font(Theme.Typeface.caption)
            }
            content
        }
    }
}

extension Block where Trailing == EmptyView {
    init(_ title: String, note: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, note: note, trailing: { EmptyView() }, content: content)
    }
}

extension View {
    /// Lists and forms drawn on the page color instead of the system's grouped gray.
    func paperList() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.Palette.page)
            .font(Theme.Typeface.body)
    }

    /// Floating control on glass, the only place content-area glass is used. Already on glass (`onGlass`), it is a
    /// washed field instead: glass over the frame's glass read as an opaque slab.
    func floatingGlass() -> some View { modifier(FloatingGlass()) }

    /// A card or fill color behind a shape, turned into a wash of the text color on glass (`onGlass`): a solid
    /// surface there floated apart from the material.
    func surface(_ color: Color, in shape: some Shape) -> some View { modifier(Surface(color: color, shape: shape)) }

    /// A short value field drawn as a pill, right-aligned, like `0.0 s` in system settings.
    /// A nil width fills the space offered, for text rather than a number.
    func pill(width: CGFloat? = 80, alignment: TextAlignment = .trailing) -> some View {
        textFieldStyle(.plain)
            .multilineTextAlignment(alignment)
            .monospacedDigit()
            .padding(Theme.Inset.control)
            .frame(width: width)
            .background(Theme.Palette.fill, in: .capsule)
    }

}

extension EnvironmentValues {
    /// Set on what sits on glass rather than on the paper panel (the floating Claude panel). Shared surfaces read it
    /// to wash instead of fill.
    @Entry var onGlass = false
}

private struct Surface<S: Shape>: ViewModifier {
    let color: Color
    let shape: S
    @Environment(\.onGlass) private var onGlass

    func body(content: Content) -> some View {
        content.background(onGlass ? Theme.Palette.text.opacity(Theme.Opacity.wash) : color, in: shape)
    }
}

private struct FloatingGlass: ViewModifier {
    @Environment(\.onGlass) private var onGlass

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.floating)
        if onGlass {
            content
                .background(Theme.Palette.text.opacity(Theme.Opacity.wash), in: shape)
                .overlay { shape.strokeBorder(Theme.Palette.text.opacity(Theme.Opacity.edge)) }
        } else {
            content.glassEffect(.regular, in: shape)
        }
    }
}

/// A term's folder, open or closed, and the front leaning back between the two, since SF Symbols has no open folder
/// and one symbol can't turn into another. Closed it is the `folder` symbol: the outline is the stroke centerline of the
/// symbol's design template (Regular-S), fitted to the medium symbol the sidebar draws (`FolderPart.unit`).
struct FolderIcon: View {
    var open: Bool
    var filled = false

    var body: some View {
        let t: CGFloat = open ? 1 : 0
        ZStack {
            FolderPart(kind: .fill, t: t).fill().opacity(filled ? Theme.Opacity.innerFill : 0)
            let line = StrokeStyle(lineWidth: FolderPart.stroke * Theme.Glyph.lineSize, lineCap: .round, lineJoin: .round)
            FolderPart(kind: .outline, t: t).stroke(style: line)
            FolderPart(kind: .corners, t: t).stroke(style: line).opacity(open ? 1 : 0)
        }
        .frame(width: Theme.Size.tile, height: Theme.Size.tile)
        .animation(.snappy(duration: 0.25), value: open)
        .accessibilityHidden(true)
    }
}

/// The folder at `t`, 0 closed to 1 open, in template units: y up is negative, the origin on the baseline.
struct FolderPart: Shape {
    /// `corners` rounds the open front's top corners. Closed, they would join the bar to the sides, so they fade.
    enum Kind { case outline, corners, fill }
    let kind: Kind
    var t: CGFloat

    var animatableData: CGFloat {
        get { t }
        set { t = newValue }
    }

    /// Points per template unit and the stroke, per point of type size: found by fitting the drawn closed folder to the
    /// 160pt medium `folder` (2.05 canvas px a unit, a 13px stroke), which is not the small template scaled evenly.
    static let unit: CGFloat = 2.05 / 160 // design: one-off, fitted to the folder symbol
    static let stroke: CGFloat = 13 / 160 // design: one-off, fitted to the folder symbol
    /// The template's middle, which sits at the middle of the symbol's image.
    static let middle = CGPoint(x: 53.54, y: -35.51)
    static let left: CGFloat = 13.28, right: CGFloat = 93.8, bottom: CGFloat = -3.64, top: CGFloat = -60.4, tabTop: CGFloat = -67.38 // design: one-off, folder template units
    /// The bar inside the closed folder becomes the open front's top edge, which leans `lean` to the right.
    static let bar: CGFloat = -48.7, barLeft: CGFloat = 25.2, barRight: CGFloat = 81.9 // design: one-off, folder template units
    static let flapTop: CGFloat = -44, lean: CGFloat = 8, corner: CGFloat = 9 // design: one-off, folder template units
    /// The open front's corners: rounded on top, and at the foot where it meets the back's side.
    static let round: CGFloat = 6, foot: CGFloat = 7 // design: one-off, folder template units

    func path(in rect: CGRect) -> Path {
        let u = Self.unit * Theme.Glyph.lineSize
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.midX + (x - Self.middle.x) * u, y: rect.midY + (y - Self.middle.y) * u) }
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * t }
        let edgeY = mix(Self.bar, Self.flapTop)
        let tl = pt(Self.left + Self.lean * t, edgeY), tr = pt(Self.right + Self.lean * t, edgeY)
        let bl = pt(Self.left, Self.bottom), br = pt(Self.right, Self.bottom)
        let r = Self.round * u
        func along(_ from: CGPoint, _ to: CGPoint, _ d: CGFloat) -> CGPoint {
            let dx = to.x - from.x, dy = to.y - from.y, l = (dx * dx + dy * dy).squareRoot()
            return CGPoint(x: from.x + dx / l * d, y: from.y + dy / l * d)
        }
        var p = Path()
        if kind == .corners {
            p.move(to: along(tl, tr, r))
            p.addArc(tangent1End: tl, tangent2End: bl, radius: r)
            p.move(to: along(tr, tl, r))
            p.addArc(tangent1End: tr, tangent2End: br, radius: r)
            return p
        }
        // The back: up the left side, over the tab, along the top and down the right side to the front's edge. Open,
        // its left side runs on down beside the leaning front.
        let backBottom = pt(Self.left, mix(Self.bar, Self.bottom - 12))
        p.move(to: backBottom)
        p.addArc(tangent1End: pt(Self.left, Self.tabTop), tangent2End: pt(33.5, Self.tabTop), radius: 8.5 * u)
        p.addArc(tangent1End: pt(33.5, Self.tabTop), tangent2End: pt(43.5, Self.top), radius: 5 * u)
        p.addArc(tangent1End: pt(43.5, Self.top), tangent2End: pt(Self.right, Self.top), radius: 5 * u)
        p.addArc(tangent1End: pt(Self.right, Self.top), tangent2End: pt(Self.right, Self.bar), radius: Self.corner * u)
        p.addLine(to: pt(Self.right, edgeY))
        switch kind {
        case .corners:
            break
        case .fill:
            // Both regions wound the same way, so where they meet is not cut out.
            p.addLine(to: tl)
            p.addLine(to: backBottom)
            p.closeSubpath()
            p.move(to: along(tl, tr, r * t))
            p.addArc(tangent1End: tr, tangent2End: br, radius: r * t)
            p.addArc(tangent1End: br, tangent2End: bl, radius: mix(Self.corner, 7) * u)
            p.addArc(tangent1End: bl, tangent2End: tl, radius: mix(Self.corner, Self.foot) * u)
            p.addArc(tangent1End: tl, tangent2End: tr, radius: r * t)
            p.closeSubpath()
        case .outline:
            // The front's sides and bottom: standing in the body when closed, leaning back when open, where they stop
            // short of the top corners for `corners` to round them.
            p.move(to: along(tl, bl, r * t))
            p.addArc(tangent1End: bl, tangent2End: br, radius: mix(Self.corner, Self.foot) * u)
            p.addArc(tangent1End: br, tangent2End: tr, radius: mix(Self.corner, 7) * u)
            p.addLine(to: along(tr, br, r * t))
            // Its top edge: the bar, short of the sides, when closed.
            p.move(to: CGPoint(x: mix(pt(Self.barLeft, 0).x, tl.x + r), y: tl.y))
            p.addLine(to: CGPoint(x: mix(pt(Self.barRight, 0).x, tr.x - r), y: tr.y))
        }
        return p
    }
}

/// A section in a page's own column (a course's sections, the settings sections): a line icon, the name, and an optional
/// count or chip. No colored tile: the window sidebar already uses tiles, and a second column of them read as a repeat.
/// The app's icon: an outline symbol in the tile-wide icon column, with no tile behind it. Sidebars, section columns
/// and the search palette all use it.
struct LineIcon: View {
    let symbol: String
    var font: Font = Theme.Glyph.line
    /// The chosen row's icon: the outline keeps its weight and its inside gets a faint fill of the same color. A solid
    /// `.fill` symbol stood out as a block, white in dark, among the outlines. Open line symbols (#, a chart line) have
    /// no inside and stay as they are.
    var filled = false

    var body: some View {
        ZStack {
            if filled, Self.hasFill(symbol) { glyph(symbol + ".fill").opacity(Theme.Opacity.innerFill) }
            glyph(symbol)
        }
    }

    /// Asked first, since drawing a symbol that doesn't exist logs a warning on every render.
    static func hasFill(_ symbol: String) -> Bool {
        #if os(macOS)
        NSImage(systemSymbolName: symbol + ".fill", accessibilityDescription: nil) != nil
        #else
        UIImage(systemName: symbol + ".fill") != nil
        #endif
    }

    func glyph(_ symbol: String) -> some View {
        // One font size for every symbol, not each fitted into a square: fitting shrank wide symbols (the cap, two
        // people) and so thinned their strokes next to square ones. The fixed frame keeps a wide or tall symbol from
        // moving its row's text. The sidebar list scales its icons up a step (`imageScale(.large)`), so the scale is
        // pinned too, or the sidebar's symbols came out a size above every other list's. The weight is pinned as well:
        // a `.fontWeight` around it (a chosen row's semibold) applies on top of the font, so the breadcrumb's and a
        // chosen row's symbols came out heavier than the sidebar's.
        Image(systemName: symbol)
            .font(font)
            .fontWeight(.regular)
            .imageScale(.medium)
            .frame(width: Theme.Size.tile, height: Theme.Size.tile)
    }
}

struct ColumnRow<Trailing: View>: View {
    let title: String
    let symbol: String
    let chosen: Bool
    /// The chosen row's icon and fill: the course accent, or the plain fill outside a course.
    var tint: Color = Theme.Palette.text
    var fill: Color = Theme.Palette.fill
    @ViewBuilder var trailing: Trailing

    /// Where the title starts, for sub-rows that line up under it.
    static var titleInset: CGFloat { Theme.Inset.listRow.leading + Theme.Size.tile + gap }
    static var gap: CGFloat { Theme.Space.s + 2 }

    var body: some View {
        HStack(spacing: Self.gap) {
            LineIcon(symbol: symbol, filled: chosen).foregroundStyle(chosen ? tint : Theme.Palette.textSecondary)
            Text(title)
            Spacer()
            trailing
        }
        // Slimmer than a list row: the icon column is already tile-tall, and the list row's padding on top of it
        // spaced the column wider than the window sidebar beside it.
        .padding(.horizontal, Theme.Inset.listRow.leading)
        .padding(.vertical, Theme.Space.xs)
        .foregroundStyle(Theme.Palette.text)
        .fontWeight(chosen ? .semibold : .regular)
        .background(chosen ? fill : .clear, in: .rect(cornerRadius: Theme.Radius.control))
        .contentShape(.rect)
    }
}

extension ColumnRow where Trailing == EmptyView {
    init(title: String, symbol: String, chosen: Bool) {
        self.init(title: title, symbol: symbol, chosen: chosen) { EmptyView() }
    }
}

extension View {
    // In place of a scroll bar: an edge fades only while there is more past it, so a list at rest isn't faded.
    // The mask also clips, which a Mac view otherwise doesn't (the sidebar's terms showed over the window buttons).
    func overflowFade(_ axis: Axis) -> some View { modifier(OverflowFade(axis: axis)) }
}

private struct OverflowFade: ViewModifier {
    let axis: Axis
    @State private var edges = Edge.Set()

    func body(content: Content) -> some View {
        let vertical = axis == .vertical
        let (start, end): (Edge.Set, Edge.Set) = vertical ? (.top, .bottom) : (.leading, .trailing)
        let (from, to): (UnitPoint, UnitPoint) = vertical ? (.top, .bottom) : (.leading, .trailing)
        let stack = vertical ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        return content
            // Not .hidden: with scroll bars set to always show, that still reserved the bar's height below a row.
            .scrollIndicators(.never)
            .onScrollGeometryChange(for: Edge.Set.self) { g in
                let (offset, visible, size) = vertical
                    ? (g.visibleRect.minY, g.visibleRect.maxY, g.contentSize.height)
                    : (g.visibleRect.minX, g.visibleRect.maxX, g.contentSize.width)
                var past = Edge.Set()
                if offset > 1 { past.insert(start) }
                if visible < size - 1 { past.insert(end) }
                return past
            } action: { _, past in
                withAnimation(.easeOut(duration: 0.15)) { edges = past }
            }
            .mask {
                stack {
                    LinearGradient(colors: [edges.contains(start) ? .clear : .primary, .primary], startPoint: from, endPoint: to)
                        .frame(width: vertical ? nil : Theme.Space.xl, height: vertical ? Theme.Space.xl : nil)
                    Rectangle()
                    LinearGradient(colors: [.primary, edges.contains(end) ? .clear : .primary], startPoint: from, endPoint: to)
                        .frame(width: vertical ? nil : Theme.Space.xl, height: vertical ? Theme.Space.xl : nil)
                }
            }
    }
}
