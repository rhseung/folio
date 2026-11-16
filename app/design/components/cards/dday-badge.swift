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

extension DueUrgency {
    static func text(_ due: Date, studyDays days: Int, settings: UrgencySettings) -> String {
        let time = due.formatted(date: .omitted, time: .shortened)
        return switch DueUrgency(studyDays: days, settings: settings) {
        case .urgent: String(localized: days == 0 ? .todayDeadlinesTodayAt(time) : .todayDeadlinesTomorrowAt(time))
        case .soon: String(localized: .todayDeadlinesInDays(days))
        case .later: due.formatted(.dateTime.month().day().weekday())
        }
    }
}
