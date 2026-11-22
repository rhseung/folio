import FolioDomain
import SwiftUI

struct ProblemDraftSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent
    @State private var model: ProblemDraftModel

    init(workspace: Workspace, course: LoadedCourse, material: UUID) {
        _model = State(initialValue: ProblemDraftModel(workspace: workspace, course: course, material: material))
    }

    var body: some View {
        SheetForm(
            title: model.sheetTitle, confirm: model.confirmTitle, isDisabled: !model.canAccept, carded: false, width: Theme.Size.solveSetup,
            deleteTitle: String(localized: .problemDraftDiscard), onDelete: model.discard
        ) {
            Card {
                FormRow(label: String(localized: .problemSetFieldTitle), last: true) {
                    InlineField(String(localized: .problemSetFieldTitleExample), text: $model.title)
                }
            }
            Card {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach($model.rows) { $row in
                            DraftRow(
                                row: $row, caption: model.caption(row.problem), units: model.unitOptions, accent: accent.color,
                                last: row.id == model.rows.last?.id
                            ) {
                                model.toggle(row.id)
                            }
                        }
                    }
                }
                .overflowFade(.vertical)
                .frame(maxHeight: Theme.Size.cardDrafts)
            }
        } onConfirm: {
            if model.accept() { dismiss() }
        }
        .confirming($model.pending)
        .onChange(of: model.finished) { if model.finished { dismiss() } }
    }
}

// 줄을 누르면 받을지 고르고, 오른쪽에서 단원을 고친다. 단원을 고치는 칸은 줄의 단추 밖에 두어 누르면 받기가 바뀌지 않는다.
private struct DraftRow: View {
    @Binding var row: ProblemDraftModel.Row
    let caption: String
    let units: [SelectOption<UUID>]
    let accent: Color
    let last: Bool
    let toggle: () -> Void

    var body: some View {
        CardRow(last: last) {
            Button(action: toggle) {
                HStack(alignment: .top, spacing: Theme.Space.m) {
                    Image(systemName: row.kept ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(row.kept ? accent : Theme.Palette.textTertiary).accessibilityHidden(true)
                    Text(verbatim: row.problem.number).font(Theme.Typeface.bodyStrong).monospacedDigit()
                        .frame(width: Theme.Size.solveCell, alignment: .leading)
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        StudyText(text: row.problem.text).lineLimit(3)
                        Text(caption).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.pointing(.plain))
            .accessibilityAddTraits(row.kept ? .isSelected : [])
            MultiCombobox(selection: $row.problem.unitIds, options: units, prompt: String(localized: .commonNone))
                .fixedSize()
        }
    }
}
