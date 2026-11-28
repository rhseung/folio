import FolioDomain
import SwiftUI

// 계획의 오늘 줄이다. 정리 노트 하나가 한 줄이고 단계는 오른쪽의 칩이다. 과목의 계획 블록, 시험 화면, 오늘 화면이 함께 쓴다.
struct PlanRowView: View {
    let model: PlanModel
    let row: PlanRow
    var last = false
    @Environment(\.openLink) private var openLink

    var body: some View {
        let detail = model.detail(row)
        CardRow(last: last) {
            if model.showsCourse { CourseMark(model.workspace, row.courseId) }
            FoldingRow {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(row.title).font(Theme.Typeface.bodyStrong).lineLimit(1)
                        .foregroundStyle(row.isDone ? Theme.Palette.textTertiary : Theme.Palette.text)
                    if !detail.isEmpty {
                        Text(detail).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary).lineLimit(1)
                    }
                }
                .opens(model.destination(row, stage: nil) == nil ? nil : { open(nil) })
            } control: {
                // 좁은 칸에서는 칩이 줄을 바꾼다. 넓은 칸에서는 칩이 제 폭을 먼저 받고 이름이 남은 폭에서 줄어든다.
                FlowLayout(spacing: Theme.Space.s, centered: true) {
                    if row.isLate { Badge(String(localized: .planLate), tone: .warning) }
                    if let badge = model.badge(row) {
                        Button {
                            open(nil)
                        } label: {
                            Badge(badge.text, tone: badge.tone).contentShape(TouchTarget())
                        }
                        .buttonStyle(.pointing(.plain))
                    }
                    ForEach(model.steps(row)) { step in
                        PlanStepChip(label: model.chip(step, in: row), progress: step.progress) { press(step) }
                    }
                }
                .layoutPriority(1)
                if !row.commands(today: model.today).isEmpty {
                    PageMenuButton { ItemMenu(source: PlanRowMenuSource(model: model, row: row)) }
                }
            }
        }
        .courseAccent(model.accent(row))
        .contextMenu { ItemMenu(source: PlanRowMenuSource(model: model, row: row)) }
    }

    func press(_ step: PlanRow.Step) {
        if model.destination(row, stage: step.stage) == nil {
            model.toggle(step, in: row)
        } else {
            open(step.stage)
        }
    }

    func open(_ stage: PlanStage?) {
        switch model.destination(row, stage: stage) {
        case .link(let link, let beside):
            openLink(link, course: row.courseId)
            if let beside { openLink(beside, in: .beside, course: row.courseId) }
        case .solve(let request): openLink.solve(request)
        case nil: break
        }
    }
}

// 끝낸 단계는 바탕 없이 조용하게 두고, 하는 중인 단계만 과목 색이다. 하는 중인 칩은 한 만큼 왼쪽부터 짙게 찬다. 할 단계는 회색 칩이다.
private struct PlanStepChip: View {
    let label: String
    let progress: PlanProgress
    let action: () -> Void
    @Environment(\.accent) private var accent

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: progress.isDone ? "checkmark.circle" : "circle")
                .labelStyle(GhostLabelStyle())
                .font(Theme.Typeface.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(ink)
                .lineLimit(1)
                .fixedSize()
                .chip(.small, fill: fill)
                .background(alignment: .leading) { filled }
                .clipShape(.capsule)
                .contentShape(TouchTarget())
        }
        .buttonStyle(.pointing(.plain))
        .accessibilityValue(Text(.planStepProgressValue(progress.done, progress.total)))
    }

    @ViewBuilder var filled: some View {
        if progress.isStarted, !progress.isDone {
            GeometryReader { box in accent.read.frame(width: box.size.width * progress.fraction) }
        }
    }

    var ink: Color {
        if progress.isDone { return Theme.Palette.textTertiary }
        return progress.isStarted ? accent.ink : Theme.Palette.textSecondary
    }

    var fill: Color {
        if progress.isDone { return .clear }
        return progress.isStarted ? accent.tint : Theme.Palette.fill
    }
}
