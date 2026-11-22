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

// 받기 표시와 번호, 문제 글을 누르면 받을지 고르고, 단원은 그 옆의 칸에서 고친다. 글과 단원 칸을 `FoldingRow` 하나에 두어,
// 글이 `draftProblemText`보다 좁아지면 단원 칸이 글 아래로 내려간다.
private struct DraftRow: View {
    @Binding var row: ProblemDraftModel.Row
    let caption: String
    let units: [SelectOption<UUID>]
    let accent: Color
    let last: Bool
    let toggle: () -> Void

    var body: some View {
        CardRow(last: last) {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                Button(action: toggle) {
                    HStack(spacing: Theme.Space.m) {
                        Image(systemName: row.kept ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(row.kept ? accent : Theme.Palette.textTertiary).accessibilityHidden(true)
                        Text(verbatim: row.problem.number).font(Theme.Typeface.bodyStrong).monospacedDigit()
                            .frame(width: Theme.Size.solveCell, alignment: .leading)
                    }
                    .frame(minHeight: Theme.Size.touchTarget, alignment: .top)
                    .contentShape(.rect)
                }
                .buttonStyle(.pointing(.plain))
                .accessibilityAddTraits(row.kept ? .isSelected : [])
                FoldingRow(labelRoom: Theme.Size.draftProblemText) {
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        StudyText(text: row.problem.text).lineLimit(4)
                        Text(caption).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                    }
                    .contentShape(.rect)
                    .onTapGesture(perform: toggle)
                    .accessibilityAddTraits(.isButton).accessibilityAddTraits(row.kept ? .isSelected : [])
                } control: {
                    MultiCombobox(selection: $row.problem.unitIds, options: units, prompt: String(localized: .commonNone))
                        .fixedSize()
                }
            }
        }
    }
}
