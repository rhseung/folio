import FolioDomain
import SwiftUI

struct DateChip: View {
    @Binding var date: Date
    var showsTime = true
    @State private var open = false

    var body: some View {
        Button {
            open = true
        } label: {
            Text(date.formatted(showsTime ? .dateTime.month().day().weekday().hour().minute() : .dateTime.year().month().day().weekday()))
                .monospacedDigit()
                .chip()
        }
        .buttonStyle(.pointing(.plain))
        .popover(isPresented: $open, arrowEdge: .bottom) {
            DatePanel(date: $date, showsTime: showsTime) { if !showsTime { open = false } }
                .padding(Theme.Space.l)
                .frame(width: 280)
        }
    }
}
