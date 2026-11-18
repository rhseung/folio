import FolioDomain
import SwiftUI

struct DdayBadge: View {
    let days: Int
    let urgency: UrgencySettings

    // 남은 날이 D-day로 세는 범위의 끝에서 0으로 갈수록 회색에서 경고색, 위험색으로 옮겨 간다.
    static func heat(_ days: Int, _ urgency: UrgencySettings) -> Color {
        let horizon = max(urgency.examNearDays, 1)
        let t = 1 - Double(min(max(days, 0), horizon)) / Double(horizon)
        return t < 0.5
            ? Theme.Palette.textSecondary.mix(with: Theme.Palette.warning, by: t * 2)
            : Theme.Palette.warning.mix(with: Theme.Palette.danger, by: (t - 0.5) * 2)
    }

    var body: some View {
        let color = Self.heat(days, urgency)
        let urgent = ExamUrgency(days: days, settings: urgency) == .urgent
        Badge(RelativeDate.dday(days: days), color: color)
            .phaseAnimator([false, true], trigger: urgent) { chip, lit in
                chip.scaleEffect(lit && urgent ? 1.06 : 1)
            } animation: { _ in
                Theme.Motion.pulse
            }
    }
}
