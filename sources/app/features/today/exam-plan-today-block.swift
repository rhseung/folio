import FolioDomain
import SwiftUI

struct ExamPlanTodayBlock: View {
    @State private var model: ExamPlanTodayModel

    init(workspace: Workspace) {
        _model = State(initialValue: ExamPlanTodayModel(workspace: workspace))
    }

    var body: some View {
        let items = model.items
        if !items.isEmpty {
            Block(String(localized: .examsPlan), note: model.note(items)) {
                Card {
                    ForEach(Array(items.enumerated()), id: \.element.item.id) { i, entry in
                        let done = model.isDone(entry)
                        CardRow(last: i == items.count - 1) {
                            CheckCircle(on: done) { model.toggle(entry) }
                                .help(Text(done ? .examsPlanUndo : .examsPlanCheck))
                                .courseAccent(model.workspace.accent(entry.courseId))
                            CourseMark(model.workspace, entry.courseId)
                            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                Text(entry.item.title).font(Theme.Typeface.bodyStrong).strikethrough(done)
                                Text(model.detail(entry))
                                    .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary)
                            }
                            Spacer()
                        }
                        .contentShape(.rect)
                        .contextMenu {
                            PlanItemMenu(courseId: entry.courseId, examId: entry.exam.id, item: entry.item.id, done: done) {
                                model.toggle(entry)
                            }
                        }
                    }
                }
            }
            .task(id: model.courseIds) { model.load() }
        }
    }
}
