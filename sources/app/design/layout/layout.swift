import FolioDomain
import SwiftUI

extension EnvironmentValues {
    @Entry var pageGutter: CGFloat = Theme.Space.xxl
}

extension EnvironmentValues {
    @Entry var revealsOverflow = false
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
