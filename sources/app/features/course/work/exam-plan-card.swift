import FolioActions
import FolioDomain
import SwiftUI

struct ExamPlanCard: View {
    let model: ExamsModel
    let exam: Exam
    @State private var day = Date.now
    @State private var title = ""
    @State private var unit: UUID?

    var body: some View {
        let items = model.plan(exam)
        let today = model.today
        Card {
            CardRow {
                Text(.examsPlan).font(Theme.Typeface.bodyStrong)
                Text(model.planLine(items))
                    .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).monospacedDigit()
                Spacer(minLength: 0)
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                let on = model.done.contains(item.id)
                CardRow {
                    CheckCircle(on: on) { model.toggle(item.id) }.help(Text(on ? .examsPlanUndo : .examsPlanCheck))
                    Text(model.dayLabel(items, at: i))
                        .font(Theme.Typeface.caption.weight(item.day == today ? .semibold : .regular)).monospacedDigit()
                        .foregroundStyle(
                            on
                                ? Theme.Palette.textTertiary
                                : item.day < today
                                    ? Theme.Palette.danger
                                    : item.day == today ? Theme.Palette.text : Theme.Palette.textSecondary
                        )
                        .lineLimit(1)
                        .frame(width: ExamsView.dateColumn, alignment: .leading)
                    Text(item.title).lineLimit(1)
                        .strikethrough(on, color: Theme.Palette.textTertiary)
                        .foregroundStyle(on ? Theme.Palette.textTertiary : Theme.Palette.text)
                    if let target = model.targetTitle(item) {
                        Text(target).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Button {
                        model.removePlanItem(item.id, of: exam)
                    } label: {
                        Image(systemName: "xmark").foregroundStyle(Theme.Palette.textTertiary)
                    }
                    .buttonStyle(.ghost)
                    .help(Text(.examsPlanRemove))
                }
                .contentShape(.rect)
                .contextMenu {
                    PlanItemMenu(courseId: model.course.id, examId: exam.id, item: item.id, done: on) { model.toggle(item.id) }
                }
            }
            CardRow(last: true) {
                DateChip(date: $day, showsTime: false)
                TextField(String(localized: .examsPlanPrompt), text: $title).textFieldStyle(.plain).onSubmit(add)
                SearchSelect(selection: $unit, options: model.targets(exam))
                Button(.commonAdd, action: add).buttonStyle(.pointing(.bordered)).disabled(!model.canAdd(item))
            }
        }
        .onAppear { day = model.firstPlanDay }
    }

    var item: ExamPlanAdd { model.planItem(exam, title: title, day: day, unit: unit) }

    func add() {
        guard model.add(item) else { return }
        title = ""
    }
}
