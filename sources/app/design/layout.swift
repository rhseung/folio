import FolioDomain
import SwiftUI

struct Page<Content: View, Backdrop: View>: View {
    var maxWidth: CGFloat = Theme.Size.pageMaxWidth
    @ViewBuilder var backdrop: Backdrop
    @ViewBuilder var content: Content
    // private으로 두지 않는다. private 속성이 있으면 memberwise init도 private이 된다.
    @Environment(\.linkFocus) var focus
    @Environment(\.pageGutter) var gutter

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // LazyVStack을 쓰지 않는다. lazy stack은 애니메이션 중에 페이지 폭이 바뀌면(과목 열이 붙거나 숨을 때)
                // 보이는 블록을 제자리에 두려고 스크롤 위치를 옮기고, 그래서 페이지가 0.25초 동안 위아래로 흔들렸다.
                // 좁은 페이지가 블록을 더 높게 쌓을수록 더 심했다. 페이지에는 블록이 몇 개뿐이고 긴 목록이 없다.
                VStack(alignment: .leading, spacing: Theme.Space.section) { content }
                    // 페이드가 숨긴 스크롤 막대 설정은 environment를 통해 안쪽 모든 것에 전달된다. 페이지 위의 텍스트
                    // 영역과 시트가 자기 막대를 지키도록 여기서 되돌린다.
                    .scrollIndicators(.automatic)
                    .frame(maxWidth: maxWidth, alignment: .leading)
                    .padding(.horizontal, gutter)
                    .padding(.top, Theme.Space.xl)
                    .clearOfColumnButtons(inset: Theme.Space.xl)
                    .padding(.bottom, Theme.Space.xxl * 2)
                    .frame(maxWidth: .infinity)
                    .background(alignment: .top) { backdrop }
                    .pageScrollWithoutBounce()
            }
            .overflowFade(.vertical)
            .task(id: focus) {
                guard let focus else { return }
                try? await Task.sleep(for: .milliseconds(100))
                withAnimation(.snappy) { proxy.scrollTo(focus, anchor: UnitPoint(x: 0.5, y: 0.2)) }
            }
        }
        .background(Theme.Palette.page)
        .scrollEdgeEffectHidden(true, for: .top)
        .foregroundStyle(Theme.Palette.text)
        .font(Theme.Typeface.body)
    }
}

extension EnvironmentValues {
    @Entry var pageGutter: CGFloat = Theme.Space.xxl
}

extension Page where Backdrop == EmptyView {
    init(maxWidth: CGFloat = Theme.Size.pageMaxWidth, @ViewBuilder content: () -> Content) {
        self.init(maxWidth: maxWidth, backdrop: { EmptyView() }, content: content)
    }
}

struct PageHeader<Chips: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var chips: Chips

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.tight) { chips }
            Text(title).font(Theme.Typeface.pageTitle).lineLimit(1)
            if let subtitle { Text(subtitle).foregroundStyle(Theme.Palette.textTertiary) }
        }
    }
}

extension PageHeader where Chips == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

// safe area에서 멈추면 열 위쪽 옆의 경계선이 빠졌으므로, 띠 없는 툴바 아래까지 열 배경과 함께 올린다.
struct ColumnDivider: View {
    var body: some View { Theme.Palette.line.frame(width: 1).ignoresSafeArea() }
}

extension EnvironmentValues {
    @Entry var revealsOverflow = false
}

struct Crumb {
    var title: String
    var symbol: String?
    var dot: Color?
    var action: (() -> Void)?
    var rename: (() -> Void)?
}

@MainActor @Observable final class CrumbTrail {
    private var levels: [Int: (owner: UUID, crumb: Crumb)] = [:]
    var crumbs: [Crumb] { levels.keys.sorted().compactMap { levels[$0]?.crumb } }

    func set(_ crumb: Crumb, level: Int, owner: UUID) { levels[level] = (owner, crumb) }
    // 페이지를 바꾸면 새 페이지가 옛 페이지가 사라지기 전에 나타나므로, 자기가 둔 단계만 지운다.
    func clear(level: Int, owner: UUID) { if levels[level]?.owner == owner { levels[level] = nil } }

    private(set) var column: ColumnCommand?
    @ObservationIgnored private var columnOwner: UUID?

    func setColumn(_ command: ColumnCommand, owner: UUID) {
        columnOwner = owner
        column = command
    }

    func clearColumn(owner: UUID) {
        guard columnOwner == owner else { return }
        columnOwner = nil
        column = nil
    }

    private(set) var outline: OutlineCommand?
    @ObservationIgnored private var outlineOwner: UUID?

    func setOutline(_ command: OutlineCommand, owner: UUID) {
        outlineOwner = owner
        outline = command
    }

    func clearOutline(owner: UUID) {
        guard outlineOwner == owner else { return }
        outlineOwner = nil
        outline = nil
    }
}

struct OutlineCommand {
    var shown: Bool
    var toggle: @MainActor () -> Void
}

extension FocusedValues {
    @Entry var outlineCommand: OutlineCommand?
}

extension View {
    func crumb(_ title: String, level: Int, symbol: String? = nil, action: (() -> Void)? = nil, rename: (() -> Void)? = nil) -> some View {
        modifier(CrumbStep(title: title, level: level, symbol: symbol, action: action, rename: rename))
    }
}

private struct CrumbStep: ViewModifier {
    let title: String
    let level: Int
    let symbol: String?
    let action: (() -> Void)?
    let rename: (() -> Void)?
    @Environment(CrumbTrail.self) private var trail: CrumbTrail?
    @State private var owner = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear(perform: register)
            .onChange(of: title) { register() }
            .onChange(of: symbol) { register() }
            .onDisappear { trail?.clear(level: level, owner: owner) }
    }

    func register() { trail?.set(Crumb(title: title, symbol: symbol, action: action, rename: rename), level: level, owner: owner) }
}

struct Breadcrumb: View {
    let crumbs: [Crumb]
    let foldWidth: CGFloat
    let maxWidth: CGFloat
    static let minWidth: CGFloat = 160
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
                    .padding(.horizontal, -Theme.Space.s)
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
            } else if i == crumbs.count - 1, let rename = crumb.rename {
                Button(crumb.title, action: rename).buttonStyle(.pointing(.plain)).help(Text(.designCrumbRenameHelp))
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

struct PageBar<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing
    @Environment(\.columnButtons) private var columnButtons

    var body: some View {
        let afterButtons = Theme.Space.s + CGFloat(columnButtons) * (Theme.Size.toolbarButton + Theme.Space.s)
        VStack(spacing: 0) {
            HStack(spacing: Theme.Space.xxs) {
                leading
                Spacer(minLength: Theme.Space.s)
                trailing
            }
            .lineLimit(1)
            .buttonStyle(.toolbar)
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .padding(.leading, columnButtons > 0 ? afterButtons : Theme.Space.m)
            .padding(.trailing, Theme.Space.m)
            .padding(.vertical, columnButtons > 0 ? Theme.Space.s : Theme.Space.xs)
            Theme.Palette.lineSoft.frame(height: 1)
        }
    }
}

struct Block<Content: View, Trailing: View>: View {
    let title: String
    var note: String?
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            BlockHeading {
                heading
                if let note { noteText(note) } else { Color.clear.frame(width: 0, height: 0) }
                action
            }
            content
        }
    }
}

extension Block {
    var heading: some View {
        Text(title).font(Theme.Typeface.sectionTitle).foregroundStyle(Theme.Palette.textSecondary).lineLimit(1)
    }

    // `BlockHeading`이 늘 하위 뷰 하나를 받도록, 비었거나 여러 뷰여도 stack에 담는다.
    var action: some View { HStack(spacing: Theme.Space.s) { trailing }.font(Theme.Typeface.caption).lineLimit(1).fixedSize() }

    func noteText(_ note: String) -> some View {
        Text(note).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
    }
}

// `ViewThatFits`가 아니라 layout으로 만든다. 페이지 scroll view 안에서 `ViewThatFits`는 고르지 않은 후보만큼 페이지의
// 스크롤 높이를 늘렸다.
struct BlockHeading: Layout {
    var spacing: CGFloat = Theme.Space.s
    var lineSpacing: CGFloat = Theme.Space.xxs

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let p = plan(proposal.width, subviews)
        return CGSize(width: p.width, height: p.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let p = plan(bounds.width, subviews)
        let (title, note, action) = (subviews[0], subviews[1], subviews[2])
        let titleSize = title.sizeThatFits(ProposedViewSize(width: p.titleWidth, height: nil))
        let actionSize = action.sizeThatFits(.unspecified)
        let baseline = title.dimensions(in: ProposedViewSize(titleSize))[VerticalAlignment.firstTextBaseline]

        title.place(at: CGPoint(x: bounds.minX, y: bounds.minY), proposal: ProposedViewSize(width: p.titleWidth, height: nil))
        let actionBaseline = action.dimensions(in: .unspecified)[VerticalAlignment.firstTextBaseline]
        action.place(
            at: CGPoint(x: bounds.maxX - actionSize.width, y: bounds.minY + max(0, baseline - actionBaseline)), proposal: .unspecified)
        let noteProposal = ProposedViewSize(width: p.oneLine ? note.sizeThatFits(.unspecified).width : bounds.width, height: nil)
        if p.oneLine {
            let noteBaseline = note.dimensions(in: noteProposal)[VerticalAlignment.firstTextBaseline]
            note.place(
                at: CGPoint(x: bounds.minX + titleSize.width + spacing, y: bounds.minY + max(0, baseline - noteBaseline)),
                proposal: noteProposal)
        } else {
            note.place(at: CGPoint(x: bounds.minX, y: bounds.minY + p.lineHeight + lineSpacing), proposal: noteProposal)
        }
    }

    private func plan(_ offered: CGFloat?, _ subviews: Subviews) -> (
        width: CGFloat, height: CGFloat, titleWidth: CGFloat, oneLine: Bool, lineHeight: CGFloat
    ) {
        let (title, note, action) = (subviews[0], subviews[1], subviews[2])
        let t = title.sizeThatFits(.unspecified), n = note.sizeThatFits(.unspecified), a = action.sizeThatFits(.unspecified)
        let hasNote = n.width > 0, hasAction = a.width > 0
        let full = t.width + (hasNote ? spacing + n.width : 0) + (hasAction ? spacing + a.width : 0)
        let width = offered.flatMap { $0.isFinite ? $0 : nil } ?? full
        let oneLine = !hasNote || full <= width
        let room = width - (hasAction ? spacing + a.width : 0)
        let titleWidth = min(t.width, oneLine ? room - (hasNote ? spacing + n.width : 0) : room)
        let lineHeight = max(title.sizeThatFits(ProposedViewSize(width: max(titleWidth, 0), height: nil)).height, a.height)
        let height =
            oneLine
            ? max(lineHeight, n.height) : lineHeight + lineSpacing + note.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        return (width, height, max(titleWidth, 0), oneLine, lineHeight)
    }
}

extension Block where Trailing == EmptyView {
    init(_ title: String, note: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, note: note, trailing: { EmptyView() }, content: content)
    }
}

extension View {
    func paperList() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.Palette.page)
            .font(Theme.Typeface.body)
    }

    func floatingGlass() -> some View { modifier(FloatingGlass()) }

    func surface(_ color: Color, in shape: some Shape) -> some View { modifier(Surface(color: color, shape: shape)) }

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

// SF Symbols에는 열린 폴더가 없고 기호 하나를 다른 기호로 바꾸며 움직일 수 없으므로 직접 그린다. 닫힌 모양의 외곽선은
// `folder` 기호 디자인 템플릿(Regular-S)의 획 중심선을 사이드바가 그리는 medium 기호에 맞춘 것이다.
struct FolderIcon: View {
    var open: Bool
    var filled = false
    var duotone = false

    var body: some View {
        let t: CGFloat = open ? 1 : 0
        ZStack {
            FolderPart(kind: .fill, t: t).fill().opacity(filled ? Theme.Opacity.innerFill : duotone ? Theme.Opacity.duotone : 0)
            let line = StrokeStyle(lineWidth: FolderPart.stroke * Theme.Glyph.lineSize, lineCap: .round, lineJoin: .round)
            FolderPart(kind: .outline, t: t).stroke(style: line)
            FolderPart(kind: .corners, t: t).stroke(style: line).opacity(open ? 1 : 0)
        }
        .frame(width: Theme.Size.tile, height: Theme.Size.tile)
        .animation(Theme.Motion.standard, value: open)
        .accessibilityHidden(true)
    }
}

struct FolderPart: Shape {
    enum Kind { case outline, corners, fill }
    let kind: Kind
    var t: CGFloat

    var animatableData: CGFloat {
        get { t }
        set { t = newValue }
    }

    // 그린 닫힌 폴더를 160pt medium `folder`(템플릿 단위당 2.05 캔버스 px, 13px 획)에 맞춰 찾은 값이다. 작은 템플릿을
    // 고르게 키운 값과 다르다.
    static let unit: CGFloat = 2.05 / 160  // design: one-off, fitted to the folder symbol
    static let stroke: CGFloat = 13 / 160  // design: one-off, fitted to the folder symbol
    static let middle = CGPoint(x: 53.54, y: -35.51)
    static let left: CGFloat = 13.28, right: CGFloat = 93.8, bottom: CGFloat = -3.64  // design: one-off, folder template units
    static let top: CGFloat = -60.4, tabTop: CGFloat = -67.38  // design: one-off, folder template units
    static let bar: CGFloat = -48.7, barLeft: CGFloat = 25.2, barRight: CGFloat = 81.9  // design: one-off, folder template units
    static let flapTop: CGFloat = -44, lean: CGFloat = 8, corner: CGFloat = 9  // design: one-off, folder template units
    static let round: CGFloat = 6, foot: CGFloat = 7  // design: one-off, folder template units

    func path(in rect: CGRect) -> Path {
        let u = Self.unit * Theme.Glyph.lineSize
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.midX + (x - Self.middle.x) * u, y: rect.midY + (y - Self.middle.y) * u)
        }
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
            // 두 영역을 같은 방향으로 감아야 만나는 곳이 뚫리지 않는다.
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
            p.move(to: along(tl, bl, r * t))
            p.addArc(tangent1End: bl, tangent2End: br, radius: mix(Self.corner, Self.foot) * u)
            p.addArc(tangent1End: br, tangent2End: tr, radius: mix(Self.corner, 7) * u)
            p.addLine(to: along(tr, br, r * t))
            p.move(to: CGPoint(x: mix(pt(Self.barLeft, 0).x, tl.x + r), y: tl.y))
            p.addLine(to: CGPoint(x: mix(pt(Self.barRight, 0).x, tr.x - r), y: tr.y))
        }
        return p
    }
}

struct LineIcon: View {
    let symbol: String
    var font: Font = Theme.Glyph.line
    var filled = false
    var duotone = false

    var body: some View {
        ZStack {
            if filled || duotone, Self.hasFill(symbol) {
                glyph(symbol + ".fill").opacity(filled ? Theme.Opacity.innerFill : Theme.Opacity.duotone)
            }
            glyph(symbol)
        }
    }

    // 없는 기호를 그리면 렌더할 때마다 경고가 기록되므로 먼저 확인한다.
    static func hasFill(_ symbol: String) -> Bool {
        #if os(macOS)
        NSImage(systemSymbolName: symbol + ".fill", accessibilityDescription: nil) != nil
        #else
        UIImage(systemName: symbol + ".fill") != nil
        #endif
    }

    func glyph(_ symbol: String) -> some View {
        // 기호마다 정사각형에 맞추지 않고 모든 기호에 같은 글꼴 크기를 쓴다. 맞추면 넓은 기호(학사모, 두 사람)가 줄어
        // 정사각형 기호 옆에서 획이 가늘어졌다. 고정 frame은 넓거나 높은 기호가 행의 글을 움직이지 않게 한다. 사이드바
        // 목록은 아이콘을 한 단계 키우므로(`imageScale(.large)`) scale도 고정한다. 그러지 않으면 사이드바 기호가 다른
        // 목록보다 한 크기 컸다. 굵기도 고정한다. 둘러싼 `.fontWeight`(고른 행의 semibold)는 글꼴 위에 더해져서, 위치
        // 표시와 고른 행의 기호가 사이드바보다 굵게 나왔다.
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
    var tint: Color = Theme.Palette.text
    var fill: Color = Theme.Palette.fill
    @ViewBuilder var trailing: Trailing

    static var titleInset: CGFloat { Theme.Inset.listRow.leading + Theme.Size.tile + gap }
    static var gap: CGFloat { Theme.Space.s + 2 }

    var body: some View {
        HStack(spacing: Self.gap) {
            LineIcon(symbol: symbol, filled: chosen).foregroundStyle(chosen ? tint : Theme.Palette.textSecondary)
            Text(title).lineLimit(1)
            Spacer(minLength: Theme.Space.s)
            trailing.lineLimit(1).fixedSize()
        }
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
    // 스크롤 막대 대신, 그 너머에 내용이 더 있을 때만 가장자리를 흐린다. mask는 잘라 내기도 하는데, Mac 뷰는 원래 잘라
    // 내지 않는다(사이드바의 학기가 창 버튼 위로 보였다).
    func overflowFade(_ axis: Axis) -> some View { modifier(OverflowFade(axis: axis)) }
}

private struct OverflowFade: ViewModifier {
    let axis: Axis
    @State private var edges = Edge.Set()

    func body(content: Content) -> some View {
        let vertical = axis == .vertical
        let (start, end): (Edge.Set, Edge.Set) = vertical ? (.top, .bottom) : (.leading, .trailing)
        return
            content
            // `.hidden`을 쓰지 않는다. 스크롤 막대를 늘 보이도록 설정하면 `.hidden`도 행 아래에 막대 높이를 남겼다.
            .scrollIndicators(.never)
            .onScrollGeometryChange(for: Edge.Set.self) { g in
                let (offset, visible, size) =
                    vertical
                    ? (g.visibleRect.minY, g.visibleRect.maxY, g.contentSize.height)
                    : (g.visibleRect.minX, g.visibleRect.maxX, g.contentSize.width)
                var past = Edge.Set()
                if offset > 1 { past.insert(start) }
                if visible < size - 1 { past.insert(end) }
                return past
            } action: { _, past in
                withAnimation(.easeOut(duration: 0.15)) { edges = past }
            }
            .mask { OverflowFadeMask(axis: axis, edges: edges) }
    }
}

// Claude 패널의 web view는 페이지 안에서 자기 스크롤 영역을 같은 길이로 흐린다(note.css의 `.edge-fade`).
private struct OverflowFadeMask: View {
    let axis: Axis
    let edges: Edge.Set

    var body: some View {
        let vertical = axis == .vertical
        let (start, end): (Edge.Set, Edge.Set) = vertical ? (.top, .bottom) : (.leading, .trailing)
        let (from, to): (UnitPoint, UnitPoint) = vertical ? (.top, .bottom) : (.leading, .trailing)
        let stack = vertical ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        stack {
            LinearGradient(colors: [edges.contains(start) ? .clear : .primary, .primary], startPoint: from, endPoint: to)
                .frame(width: vertical ? nil : Theme.Space.xl, height: vertical ? Theme.Space.xl : nil)
            Rectangle()
            LinearGradient(colors: [.primary, edges.contains(end) ? .clear : .primary], startPoint: from, endPoint: to)
                .frame(width: vertical ? nil : Theme.Space.xl, height: vertical ? Theme.Space.xl : nil)
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var centered = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(fit(bounds.width))
                let y = bounds.minY + row.y + (centered ? (row.height - size.height) / 2 : 0)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: fit(bounds.width))
                x += size.width + spacing
            }
        }
    }

    private func fit(_ width: CGFloat) -> ProposedViewSize {
        ProposedViewSize(width: width.isFinite ? width : nil, height: nil)
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [(items: [Int], y: CGFloat, width: CGFloat, height: CGFloat)] {
        var rows: [(items: [Int], y: CGFloat, width: CGFloat, height: CGFloat)] = []
        var current: (items: [Int], y: CGFloat, width: CGFloat, height: CGFloat) = ([], 0, 0, 0)
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(fit(width))
            let added = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if added > width, !current.items.isEmpty {
                rows.append(current)
                current = ([i], current.y + current.height + spacing, size.width, size.height)
            } else {
                current = (current.items + [i], current.y, added, Swift.max(current.height, size.height))
            }
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}
