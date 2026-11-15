import FolioDomain
import SwiftUI

struct FoldingRow<Title: View, Control: View>: View {
    // 나란히 둘 때 이름이 가져야 하는 폭이다. 이름 아래에 마감 같은 긴 설명 줄이 있으면 더 넓게 준다.
    var labelRoom: CGFloat = Theme.Size.foldingLabel
    @ViewBuilder var title: Title
    @ViewBuilder var control: Control

    var body: some View {
        // `ViewThatFits`는 ideal 폭으로 판단하는데, 이름의 ideal 폭은 한 줄 전체라서 설명이 긴 행은 넓은 창에서도
        // 접혔다. 그래서 이름의 ideal 폭을 필요한 폭으로 고정해 컨트롤의 폭만 판단에 들어가게 한다.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Space.m) {
                title.frame(idealWidth: labelRoom, alignment: .leading)
                Spacer(minLength: Theme.Space.m)
                control
            }
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                title.frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: Theme.Space.m) { control }
            }
        }
    }
}
