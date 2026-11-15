import FolioDomain
import SwiftUI

// 폭을 재서 플래그로 두지 않는다. 플래그는 넓은 상태로 시작하므로, 처음 나란히 그릴 때 두 블록의 최소 폭만큼 좁은 칸을
// 밀어냈다.
struct Fold<Content: View>: View {
    let wideFrom: CGFloat
    var spacing: CGFloat = Theme.Space.xl
    var stackSpacing: CGFloat = Theme.Space.section
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: spacing) { content }
                .frame(idealWidth: wideFrom)
            VStack(alignment: .leading, spacing: stackSpacing) { content }
        }
    }
}
