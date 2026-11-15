import FolioDomain
import SwiftUI

struct FormRow<Control: View>: View {
    let label: String
    var detail: String?
    var device = false
    var warns = false
    var last = false
    @ViewBuilder var control: Control

    var body: some View {
        CardRow(last: last) {
            FoldingRow {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    HStack(spacing: Theme.Space.tight) {
                        Text(label).lineLimit(1)
                        if device { DeviceTag() }
                    }
                    if let detail {
                        Text(detail).font(Theme.Typeface.caption).foregroundStyle(
                            warns ? Theme.Palette.warning : Theme.Palette.textTertiary)
                    }
                }
            } control: {
                control
            }
        }
    }
}
