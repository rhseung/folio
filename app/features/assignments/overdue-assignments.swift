import FolioDomain
import SwiftUI

// 마감이 지났는데 아직 할 일로 남은 과제를 페이지 맨 위에 묶는다. 내거나 포기하기 전까지 늘 보인다.
struct OverdueAssignments: View {
    @State private var model: OverdueAssignmentsModel
    @Environment(\.openLink) private var openLink
    @Environment(\.openURL) private var openURL

    init(workspace: Workspace, course: UUID? = nil) {
        _model = State(initialValue: OverdueAssignmentsModel(workspace: workspace, course: course))
    }

    var body: some View {
        let rows = model.rows(now: model.workspace.liveNow)
        Group {
            if !rows.isEmpty {
                NoticeCard(title: String(localized: .overdueTitle(rows.count)), systemImage: "exclamationmark.triangle.fill", tone: .danger)
                {
                    EmptyView()
                } rows: {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                        // Button으로 두면 안의 제출함과 못 냄 버튼이 클릭을 빼앗긴다.
                        CardRow(last: i == rows.count - 1) { content(row) }
                            .linkTarget(row.id)
                            .opens { model.edit(row) }
                            .accessibilityAction(named: Text(.commonEdit)) { model.edit(row) }
                            .contextMenu { AssignmentMenu(courseId: row.courseId, assignmentId: row.id) }
                    }
                }
            }
        }
        .sheet(item: $model.editing) { item in
            AssignmentSheet(workspace: model.workspace, course: item.course, assignment: item.assignment) { id, placement in
                openLink(AppLink(.material, id), in: placement, course: item.course.id)
            }
        }
    }

    func content(_ row: OverdueAssignmentsModel.Row) -> some View {
        FoldingRow(labelRoom: Theme.Size.overdueLabel) {
            HStack(spacing: Theme.Space.m) {
                if model.showsCourse { CourseMark(model.workspace, row.courseId) }
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                        Text(row.assignment.title).font(Theme.Typeface.bodyStrong).lineLimit(1).layoutPriority(1)
                        if model.showsCourse {
                            Text(model.courseTitle(row)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                                .lineLimit(1)
                        }
                        if row.lms != nil { Badge(String(localized: .lmsNotSubmitted), tone: .danger) }
                    }
                    HStack(spacing: Theme.Space.s) {
                        Text(row.past).foregroundStyle(Theme.Palette.danger)
                        if let ceiling = row.ceiling {
                            Text(ceiling).foregroundStyle(row.lost ? Theme.Palette.danger : Theme.Palette.textTertiary)
                        }
                    }
                    .font(Theme.Typeface.caption).monospacedDigit().lineLimit(1)
                }
            }
        } control: {
            Button(.overdueMarkMissed) { model.miss(row) }.buttonStyle(.ghost)
            // Folio에서는 이미 제출함이라 제출함 단추 대신 LMS에서 낼 곳을 연다.
            if row.submitted, let url = row.lms {
                Button(.lmsOpen) { openURL(url) }.buttonStyle(.pointing(.bordered))
            } else {
                Button(.overdueMarkSubmitted) { model.submit(row) }.buttonStyle(.pointing(.bordered))
            }
        }
    }
}
