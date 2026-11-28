import FolioDomain
import SwiftUI

struct DateChip: View {
    @Binding var selection: Date
    var showsTime = true
    // 한 학기 안의 날짜를 나란히 둘 때는 해를 빼서 좁은 칸에서도 두 칩이 한 줄에 들어가게 한다.
    var showsYear = true
    @State private var open = false

    var body: some View {
        Button {
            open = true
        } label: {
            Text(
                selection.formatted(
                    showsTime
                        ? .dateTime.month().day().weekday().hour().minute()
                        : showsYear ? .dateTime.year().month().day().weekday() : .dateTime.month().day().weekday())
            )
            .monospacedDigit()
            .chip()
        }
        .buttonStyle(.pointing(.plain))
        .popover(isPresented: $open, arrowEdge: .bottom) {
            DatePanel(date: $selection, showsTime: showsTime) { if !showsTime { open = false } }
                .padding(Theme.Space.l)
                .frame(width: 280)
        }
    }
}
