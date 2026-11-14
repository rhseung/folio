import FolioDomain
import SwiftUI

struct RequirementLine: View {
    let category: RequirementCategory
    let credits: CategoryCredits
    let header: Bool
    var title: String?

    var body: some View {
        let s = RequirementStatus(category: category, credits: credits)
        let idle = s.goal == nil && s.done + s.taking == 0
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .center, spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(title ?? category.name)
                        .font(header ? Theme.Typeface.figureSmall : Theme.Typeface.body)
                        .foregroundStyle(idle ? Theme.Palette.textTertiary : Theme.Palette.text)
                        .lineLimit(1)
                    if let note = Self.note(category, s) {
                        Text(note).font(Theme.Typeface.caption).foregroundStyle(s.over ? Theme.Palette.warning : Theme.Palette.textTertiary)
                    }
                }
                Spacer(minLength: Theme.Space.s)
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.xs) {
                    Text(s.done.formatted()).font(header ? Theme.Typeface.figureSmall : Theme.Typeface.bodyStrong)
                        .foregroundStyle(idle ? Theme.Palette.textTertiary : Theme.Palette.text)
                    if let goal = s.goal { Text("/ \(goal.formatted())").foregroundStyle(Theme.Palette.textTertiary) }
                    Text(Self.unit(s)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                }
                .monospacedDigit()
                ProgressRing(done: s.done, taking: s.taking, goal: s.goal, met: s.met, over: s.over)
            }
            if header, s.goal != nil {
                CreditBar(credits: CategoryCredits(earned: s.done, inProgress: s.taking), goal: s.goal, met: s.met, height: 6)
            }
        }
    }

    static func unit(_ s: RequirementStatus) -> String {
        String(localized: s.countsCourses ? .requirementsUnitCourses : .requirementsUnitCredits)
    }

    static func note(_ category: RequirementCategory, _ s: RequirementStatus) -> String? {
        var parts: [String] = []
        if s.taking > 0 { parts.append(String(localized: .requirementsTaking(s.taking.formatted()))) }
        if s.over, let cap = category.maxCredits {
            parts.append(String(localized: .requirementsCapExceeded(cap.formatted())))
        } else if let goal = s.goal, !s.met {
            parts.append(String(localized: .requirementsLeft((goal - s.done).formatted(), unit(s))))
        } else if let cap = category.maxCredits, cap > 0, cap != category.minCredits {
            parts.append(String(localized: .requirementsCap(cap.formatted())))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
