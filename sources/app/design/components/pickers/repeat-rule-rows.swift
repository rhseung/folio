import FolioDomain
import SwiftUI

struct RepeatRuleRows: View {
    @Binding var rule: AssignmentRepeat
    let dueWeekday: Int?
    var last = false

    var body: some View {
        FormRow(label: String(localized: .repeatPickerInterval), last: last && rule.unit != .week) {
            NumberField(value: Binding(get: { rule.every }, set: { set(every: $0) }), in: 1...30, width: 72)
            SegmentedControl(
                selection: Binding(get: { rule.unit }, set: { set(unit: $0) }),
                options: [
                    (.day, String(localized: .repeatPickerDays)), (.week, String(localized: .repeatPickerWeeks)),
                    (.month, String(localized: .repeatPickerMonths)),
                ])
        }
        if rule.unit == .week {
            FormRow(label: String(localized: .repeatPickerWeekdays), last: last) {
                ToggleGroup(
                    selection: Binding(get: { shownDays }, set: { set(weekdays: $0) }),
                    options: (1...7).map { .init(value: $0, label: ClassTime.weekdayNames[$0 - 1]) }, shape: .circle,
                    allowsEmptySelection: false)
            }
        }
    }

    private var shownDays: Set<Int> { rule.weekdays.isEmpty ? Set(dueWeekday.map { [$0] } ?? []) : Set(rule.weekdays) }

    private func set(every: Int? = nil, unit: AssignmentRepeat.Unit? = nil, weekdays: Set<Int>? = nil) {
        let days = unit.map { $0 == .week ? rule.weekdays : [] } ?? weekdays.map { Array($0) } ?? rule.weekdays
        rule = AssignmentRepeat(every: every ?? rule.every, unit ?? rule.unit, weekdays: days).normalized(dueWeekday: dueWeekday)
    }
}
