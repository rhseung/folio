import FolioDomain
import SwiftUI

struct MonthCalendar: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.accent) private var accent
    @Binding var date: Date
    @State private var month: Date?

    var body: some View {
        let calendar = workspace.calendar
        let shown = month ?? calendar.dateInterval(of: .month, for: date)!.start
        let lead = (calendar.component(.weekday, from: shown) - calendar.firstWeekday + 7) % 7
        let days = (0..<42).compactMap { calendar.date(byAdding: .day, value: $0 - lead, to: shown) }
        let columns = Array(repeating: GridItem(.fixed(34), spacing: Theme.Space.xxs), count: 7)
        VStack(spacing: Theme.Space.s) {
            HStack {
                Text(shown.formatted(.dateTime.year().month(.wide))).font(Theme.Typeface.bodyStrong)
                Spacer()
                Button(.designToday) {
                    month = nil; date = .now
                }
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
                Button {
                    month = calendar.date(byAdding: .month, value: -1, to: shown)
                } label: {
                    Image(systemName: "chevron.left")
                }
                Button {
                    month = calendar.date(byAdding: .month, value: 1, to: shown)
                } label: {
                    Image(systemName: "chevron.right")
                }
            }
            .buttonStyle(.ghost)
            LazyVGrid(columns: columns, spacing: Theme.Space.xxs) {
                ForEach(0..<7, id: \.self) { i in
                    Text(ClassTime.weekdayNames[((calendar.firstWeekday - 1 + i) % 7 + 6) % 7])
                        .font(Theme.Typeface.label)
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .frame(height: 22)
                }
                ForEach(days, id: \.self) { day in
                    let selected = calendar.isDate(day, inSameDayAs: date)
                    let inMonth = calendar.isDate(day, equalTo: shown, toGranularity: .month)
                    Button {
                        date = day
                    } label: {
                        Text("\(calendar.component(.day, from: day))")
                            .font(calendar.isDateInToday(day) ? Theme.Typeface.bodyStrong : Theme.Typeface.body)
                            .monospacedDigit()
                            .foregroundStyle(
                                selected ? Theme.Palette.onFill : inMonth ? Theme.Palette.text : Theme.Palette.textTertiary.opacity(0.6)
                            )
                            .frame(width: 32, height: 32)
                            .background(selected ? accent.color : .clear, in: .circle)
                            .overlay { if calendar.isDateInToday(day) && !selected { Circle().strokeBorder(accent.color, lineWidth: 1.5) } }
                            .contentShape(.circle)
                    }
                    .buttonStyle(.pointing(.plain))
                }
            }
        }
        .onChange(of: date) { _, new in
            if let m = month, !calendar.isDate(new, equalTo: m, toGranularity: .month) { month = nil }
        }
    }
}
