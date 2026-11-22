import FolioDomain
import SwiftUI

struct MakeProblemsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: MakeProblemsModel

    init(workspace: Workspace, course: LoadedCourse, units: [FolioDomain.Unit], count: Int? = nil) {
        _model = State(initialValue: MakeProblemsModel(workspace: workspace, course: course, units: units, count: count))
    }

    var body: some View {
        SheetForm(title: model.title, confirm: model.confirmTitle, isDisabled: !model.canConfirm, note: model.note) {
            if !model.hasKey {
                MissingKeyNotice().padding(Theme.Space.m)
            } else if let draft = model.draft {
                CardRow { Text(draft.title).font(Theme.Typeface.body.weight(.semibold)).lineLimit(1) }
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(draft.problems.enumerated()), id: \.offset) { i, p in
                            CardRow(last: i == draft.problems.count - 1) {
                                Text(verbatim: p.number).monospacedDigit().foregroundStyle(Theme.Palette.textTertiary)
                                    .frame(width: Theme.Size.solveCell, alignment: .leading)
                                StudyText(text: p.text).lineLimit(4)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
                .overflowFade(.vertical)
                .frame(maxHeight: Theme.Size.cardDrafts)
            } else {
                FormRow(label: String(localized: .makeProblemsCount), last: !model.busy && model.failure == nil) {
                    Select(selection: $model.count, options: model.countOptions)
                }
                if model.busy {
                    CardRow(last: model.failure == nil) {
                        ProgressView().controlSize(.small)
                        Text(.makeProblemsBusy).foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
                if let failure = model.failure {
                    CardRow(last: true) { Text(failure).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.danger) }
                }
            }
        } onConfirm: {
            if model.confirm() { dismiss() }
        }
    }
}
