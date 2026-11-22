import FolioDomain
import SwiftUI

// 행마다 폭을 맞춰 칩이 한 줄로 서게 한다.
struct ReadinessBadge: View {
    let readiness: UnitReadiness

    var body: some View {
        Badge(readiness.state.label, tone: readiness.state.tone)
            .frame(width: Theme.Size.readinessColumn, alignment: .trailing)
    }
}
