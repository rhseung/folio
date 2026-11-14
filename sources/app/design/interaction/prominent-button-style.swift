import FolioDomain
import SwiftUI

// 과목은 페이지를 자기 잉크 색(다크 모드에서는 옅은 색)으로 tint 하고, 시트는 연 뷰의 tint를 받지 않고 넘겨받은
// `accent`만 받는다. 그래서 과목 색은 둘러싼 tint가 아니라 여기서 정한다.
struct ProminentButtonStyle: PrimitiveButtonStyle {
    @Environment(\.accent) private var accent

    func makeBody(configuration: Configuration) -> some View {
        Button(configuration).buttonStyle(.pointing(.borderedProminent))
            .tint(accent == .gray ? Color.accentColor : accent.fill)
    }
}
