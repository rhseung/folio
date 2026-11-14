import FolioDomain
import SwiftUI

struct SettingTimeRow: View {
    let item: SettingItem
    @Binding var minute: Int
    var last = false

    var body: some View {
        FormRow(label: String(localized: item.name), last: last) {
            TimeMenu(minute: $minute, hours: item.hours)
        }
    }
}
