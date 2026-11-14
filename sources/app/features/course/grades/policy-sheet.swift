import FolioDomain
import SwiftUI

struct PolicySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: PolicyModel

    init(workspace: Workspace, course: LoadedCourse) {
        _model = State(initialValue: PolicyModel(workspace: workspace, course: course))
    }

    var body: some View {
        let grades = model.grades
        SheetForm(
            title: String(localized: .courseGradesPolicy), confirm: String(localized: .commonSave), disabled: model.invalid, carded: false,
            width: 560
        ) {
            if model.isRelative {
                Block(String(localized: .policySheetRelative)) {
                    Card {
                        FormRow(
                            label: String(localized: .policySheetTopShare),
                            detail: String(localized: .policySheetTopShareDetail(model.defaultTopShare)), last: true
                        ) {
                            HStack(spacing: Theme.Space.s) {
                                TextField(model.defaultTopShare, text: $model.topShare).pill(width: 72)
                                Text("%").foregroundStyle(Theme.Palette.textTertiary)
                            }
                        }
                    }
                }
            }
            Block(
                title: String(localized: .policySheetCaps), note: String(localized: .policySheetCapsNote),
                trailing: {
                    Button {
                        model.addCap()
                    } label: {
                        Label(.policySheetAddCap, systemImage: "plus")
                    }
                    .buttonStyle(.ghost).disabled(grades.isEmpty)
                }
            ) {
                Card {
                    if model.caps.isEmpty { CardRow(last: true) { EmptyLine(String(localized: .policySheetNoCaps)) } }
                    ForEach(model.caps.indices, id: \.self) { i in
                        let cap = Binding(get: { model.cap(i) }, set: { model.setCap(i, $0) })
                        CardRow(last: i == model.caps.count - 1) {
                            Text(.courseGradesAbsences)
                            TextField(String(localized: .policySheetTimes), value: cap.absences, format: .number).pill(width: 56)
                            Text(.policySheetCapFrom).foregroundStyle(Theme.Palette.textSecondary)
                            ChoiceMenu(selection: cap.maxGrade, options: grades.map { ($0.id, $0.symbol) })
                            Spacer()
                            Button {
                                model.caps.remove(at: i)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.ghost)
                            .foregroundStyle(Theme.Palette.textTertiary)
                            .help(Text(.policySheetRemoveCap))
                        }
                    }
                }
            }
            Block(String(localized: .courseGradesOtherRules)) {
                Card {
                    FormRow(label: String(localized: .policySheetLate), detail: String(localized: .policySheetLateDetail)) {
                        HStack(spacing: Theme.Space.s) {
                            TextField(String(localized: .requirementsNone), text: $model.lates).pill(width: 56)
                            Text(.policySheetLatesPerAbsence).foregroundStyle(Theme.Palette.textTertiary)
                        }
                    }
                    FormRow(label: String(localized: .courseGradesMinAttendance)) {
                        HStack(spacing: Theme.Space.s) {
                            TextField(String(localized: .requirementsNone), text: $model.ratio).pill(width: 72)
                            Text("%").foregroundStyle(Theme.Palette.textTertiary)
                        }
                    }
                    FormRow(label: String(localized: .courseGradesLateSubmission), last: true) {
                        InlineField(String(localized: .policySheetLateSubmissionExample), text: $model.late)
                    }
                }
            }
            FormTextArea(
                label: String(localized: .policySheetNotes), detail: String(localized: .policySheetNotesDetail), text: $model.notes)
        } onConfirm: {
            if model.confirm() { dismiss() }
        }
    }
}
