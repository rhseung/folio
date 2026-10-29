import FolioDomain
import SwiftUI

struct ScoreEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: ScoreEntryModel
    @State private var confirmingDelete = false

    init(workspace: Workspace, course: LoadedCourse, entry: ScoreEntry) {
        _model = State(initialValue: ScoreEntryModel(workspace: workspace, course: course, entry: entry))
    }

    var body: some View {
        SheetForm(title: model.sheetTitle, confirm: model.confirmTitle, disabled: !model.valid,
                  deleteTitle: model.isNew ? nil : String(localized: .scoreSheetRemove), onDelete: { confirmingDelete = true }) {
            // A new score is added from its component's tile, which already picked the component.
            if !model.isNew {
                FormRow(label: String(localized: .scoreSheetComponent)) {
                    ChoiceMenu(selection: $model.componentId, options: model.componentOptions)
                }
            }
            if model.hasTitle { FormRow(label: String(localized: .scoreSheetTitle)) { InlineField(String(localized: .scoreSheetTitleExample), text: $model.title) } }
            FormRow(label: String(localized: .scoreSheetScore)) {
                HStack(spacing: Theme.Space.s) {
                    TextField(String(localized: .scoreSheetScore), text: $model.score).pill(width: 72)
                    Text("/").foregroundStyle(Theme.Palette.textTertiary)
                    TextField(String(localized: .scoreSheetMax), text: $model.max).pill(width: 72)
                }
            }
            FormRow(label: String(localized: .scoreSheetMeanAndStdDev), detail: model.meanDetail) {
                HStack(spacing: Theme.Space.s) {
                    TextField(String(localized: .scoreSheetMean), text: $model.mean).pill(width: 72)
                    Text("±").foregroundStyle(Theme.Palette.textTertiary)
                    TextField(String(localized: .scoreSheetStdDev), text: $model.stdDev).pill(width: 72)
                }
            }
            FormRow(label: String(localized: .scoreSheetCounts), detail: String(localized: .scoreSheetCountsDetail), last: true) {
                ChoiceMenu(selection: $model.excused, options: [(false, String(localized: .scoreSheetCounts)), (true, String(localized: .courseGradesExcused))])
            }
        } onConfirm: {
            if model.confirm() { dismiss() }
        }
        .confirmationDialog(CourseGradesModel.removeTitle(model.entry), isPresented: $confirmingDelete) {
            Button(.commonDelete, role: .destructive) {
                model.remove()
                dismiss()
            }
        }
    }
}

struct ComponentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: ComponentModel
    @State private var confirmingDelete = false

    init(workspace: Workspace, course: LoadedCourse, component: GradeComponent) {
        _model = State(initialValue: ComponentModel(workspace: workspace, course: course, component: component))
    }

    var body: some View {
        SheetForm(title: model.sheetTitle, confirm: model.confirmTitle, disabled: model.invalid,
                  deleteTitle: model.isNew ? nil : String(localized: .componentSheetRemove), onDelete: { confirmingDelete = true }) {
            FormRow(label: String(localized: .componentSheetName)) { InlineField(String(localized: .componentSheetNameExample), text: $model.name) }
            FormRow(label: String(localized: .componentSheetGroup), detail: String(localized: .componentSheetGroupDetail)) {
                InlineField(String(localized: .componentSheetGroupExample), text: $model.group)
            }
            FormRow(label: String(localized: .componentSheetWeight)) {
                HStack(spacing: Theme.Space.s) {
                    TextField(String(localized: .componentSheetWeight), value: $model.weight, format: .number).pill(width: 72)
                    Text("%").foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            FormRow(label: String(localized: .componentSheetAggregation), last: model.aggregation == .single) {
                ChoiceMenu(selection: $model.aggregation, options: model.aggregationOptions)
            }
            if model.count != nil {
                FormRow(label: model.countLabel) {
                    ChoiceMenu(selection: $model.countValue, options: model.countOptions)
                }
            }
            // A single score is one by definition, so a count there would only contradict it.
            if model.aggregation != .single {
                FormRow(label: String(localized: .componentSheetExpectedCount), detail: String(localized: .componentSheetExpectedCountDetail), last: true) {
                    HStack(spacing: Theme.Space.tight) {
                        TextField(String(localized: .componentSheetUnset), value: $model.expectedCount, format: .number).pill(width: 110)
                        Text(.componentSheetTimesUnit).foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
            }
        } onConfirm: {
            if model.confirm() { dismiss() }
        }
        .confirmationDialog(CourseGradesModel.removeTitle(model.component), isPresented: $confirmingDelete) {
            Button(.commonDelete, role: .destructive) {
                model.remove()
                dismiss()
            }
        } message: {
            if let message = CourseGradesModel.removeMessage(model.component, in: model.course.file) { Text(message) }
        }
    }
}

struct PolicySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: PolicyModel

    init(workspace: Workspace, course: LoadedCourse) {
        _model = State(initialValue: PolicyModel(workspace: workspace, course: course))
    }

    var body: some View {
        let grades = model.grades
        SheetForm(title: String(localized: .courseGradesPolicy), confirm: String(localized: .commonSave), disabled: model.invalid, carded: false, width: 560) {
            if model.isRelative {
                Block(String(localized: .policySheetRelative)) {
                    Card {
                        FormRow(label: String(localized: .policySheetTopShare), detail: String(localized: .policySheetTopShareDetail(model.defaultTopShare)), last: true) {
                            HStack(spacing: Theme.Space.s) {
                                TextField(model.defaultTopShare, text: $model.topShare).pill(width: 72)
                                Text("%").foregroundStyle(Theme.Palette.textTertiary)
                            }
                        }
                    }
                }
            }
            Block(title: String(localized: .policySheetCaps), note: String(localized: .policySheetCapsNote), trailing: {
                Button { model.addCap() } label: { Label(.policySheetAddCap, systemImage: "plus") }
                    .buttonStyle(.ghost).disabled(grades.isEmpty)
            }) {
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
                            Button { model.caps.remove(at: i) } label: { Image(systemName: "minus.circle") }
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
                    FormRow(label: String(localized: .courseGradesLateSubmission), last: true) { InlineField(String(localized: .policySheetLateSubmissionExample), text: $model.late) }
                }
            }
            FormTextArea(label: String(localized: .policySheetNotes), detail: String(localized: .policySheetNotesDetail), text: $model.notes, height: 96)
        } onConfirm: {
            if model.confirm() { dismiss() }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: .unspecified)
                x += size.width + spacing
            }
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [(items: [Int], y: CGFloat, width: CGFloat, height: CGFloat)] {
        var rows: [(items: [Int], y: CGFloat, width: CGFloat, height: CGFloat)] = []
        var current: (items: [Int], y: CGFloat, width: CGFloat, height: CGFloat) = ([], 0, 0, 0)
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            let added = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if added > width, !current.items.isEmpty {
                rows.append(current)
                current = ([i], current.y + current.height + spacing, size.width, size.height)
            } else {
                current = (current.items + [i], current.y, added, Swift.max(current.height, size.height))
            }
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}
