import FolioActions
import FolioDomain
import SwiftUI

extension View {
    // 열의 글꼴로 가장 넓은 시각만큼 폭을 잡는다. 고정 폭은 `오후 1:00`을 자르거나 줄을 바꿨다. 화면에 보이지 않는
    // 측정용 견본이라 verbatim으로 쓴다.
    func timeColumn() -> some View {
        ZStack(alignment: .leading) {
            Text(verbatim: "오후 12:00").hidden(); self
        }.lineLimit(1)
    }
}
