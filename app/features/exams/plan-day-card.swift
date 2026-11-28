import FolioDomain
import SwiftUI

// 계획의 다음 날 하나다. 날짜마다 작은 카드로 접고, 줄에는 이름과 단계 수만큼의 점만 둔다.
struct PlanDayCard: View {
    let model: PlanModel
    let day: PlanBoard.Day
    @Environment(\.openLink) private var openLink

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Text(model.dayLabel(day.day)).font(Theme.Typeface.bodyStrong).monospacedDigit().lineLimit(1)
                Text(model.daySummary(day)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.top, Theme.Space.m)
            .padding(.bottom, Theme.Space.xs)
            ForEach(Array(day.rows.enumerated()), id: \.element.id) { i, row in
                CardRow(last: i == day.rows.count - 1) {
                    if model.showsCourse { CourseMark(model.workspace, row.courseId) }
                    Text(row.title).lineLimit(1).layoutPriority(1)
                        .opens(model.destination(row, stage: nil) == nil ? nil : { open(row) })
                    if row.isLate { Badge(String(localized: .planLate), tone: .warning) }
                    Spacer(minLength: Theme.Space.s)
                    PlanDots(row: row)
                    PageMenuButton { ItemMenu(source: PlanRowMenuSource(model: model, row: row)) }
                }
                .courseAccent(model.accent(row))
                .contextMenu { ItemMenu(source: PlanRowMenuSource(model: model, row: row)) }
            }
        }
    }

    func open(_ row: PlanRow) {
        switch model.destination(row, stage: nil) {
        case .link(let link, let beside):
            openLink(link, course: row.courseId)
            if let beside { openLink(beside, in: .beside, course: row.courseId) }
        case .solve(let request): openLink.solve(request)
        case nil: break
        }
    }
}

private struct PlanDots: View {
    let row: PlanRow
    @Environment(\.accent) private var accent

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            // 점은 단계의 진행만큼 왼쪽부터 과목 색으로 찬다.
            ForEach(row.steps) { step in
                Circle().fill(Theme.Palette.lineStrong)
                    .overlay(alignment: .leading) { accent.color.frame(width: Theme.Size.dot * step.progress.fraction) }
                    .clipShape(.circle)
                    .frame(width: Theme.Size.dot, height: Theme.Size.dot)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(.planDots(row.doneSteps, row.steps.count)))
    }
}
