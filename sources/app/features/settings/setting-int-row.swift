import FolioDomain
import SwiftUI

struct SettingIntRow: View {
    let item: SettingItem
    @Binding var value: Int
    let unit: LocalizedStringResource
    var step = 1
    var last = false

    var body: some View {
        FormRow(label: String(localized: item.name), last: last) {
            IntScrub(value: $value, range: item.range, step: step)
            Text(unit).foregroundStyle(Theme.Palette.textSecondary)
        }
    }
}
