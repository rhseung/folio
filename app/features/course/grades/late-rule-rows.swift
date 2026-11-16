import FolioDomain
import SwiftUI

// 비운 칸의 자리 글자는 `placeholder`(과제 시트에서는 과목의 규칙)다.
struct LateRuleRows: View {
    @Binding var draft: LateRuleDraft
    var placeholder: LateRule?
    var last = false

    var body: some View {
        FormRow(label: String(localized: .lateRulePercent)) {
            HStack(spacing: Theme.Space.s) {
                TextField(
                    placeholder.map { $0.percentPerDay.formatted(.number.grouping(.never)) } ?? String(localized: .requirementsNone),
                    text: $draft.percent
                )
                .pill(width: Theme.Size.numberField)
                Text("%").foregroundStyle(Theme.Palette.textTertiary)
            }
        }
        FormRow(label: String(localized: .lateRuleDays), detail: String(localized: .lateRuleDaysDetail), last: last) {
            HStack(spacing: Theme.Space.s) {
                TextField(placeholder?.days.map(String.init) ?? String(localized: .requirementsNone), text: $draft.days)
                    .pill(width: Theme.Size.countField)
                Text(.lateRuleDaysUnit).foregroundStyle(Theme.Palette.textTertiary)
            }
        }
    }
}
