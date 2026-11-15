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

extension Page where Backdrop == EmptyView {
    init(maxWidth: CGFloat = Theme.Size.pageMaxWidth, @ViewBuilder content: () -> Content) {
        self.init(maxWidth: maxWidth, backdrop: { EmptyView() }, content: content)
    }
}
