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
        Badge(DDay.text(days), color: color)
            .phaseAnimator([false, true], trigger: urgent) { chip, lit in
                chip.scaleEffect(lit && urgent ? 1.06 : 1)
            } animation: { _ in
                Theme.Motion.pulse
            }
    }
}

extension RelativeDay {
    // 한 줄에 쓰는 마감은 과제 목록의 두 줄을 합친 것이다. 하루 안이면 남은 시간만 쓰고, 내일이나 어제면
    // 몇 시인지가 중요해서 시각을 붙인다. 그보다 멀면 날 수만 쓴다.
    static func line(until due: Date, from now: Date, settings: FolioDomain.Settings, calendar: Calendar) -> String {
        if let near = RelativeTime.text(until: due, from: now) { return near }
        let days = settings.studyDays(from: now, until: due, calendar: calendar)
        let day = text(days)
        return abs(days) <= 1 ? day + " " + TimePicker.label(calendar.minuteOfDay(due)) : day
    }
}
