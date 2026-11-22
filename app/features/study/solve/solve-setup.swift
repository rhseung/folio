import FolioDomain
import SwiftUI

struct SolveSetup: View {
    @Bindable var model: SolveModel

    var body: some View {
        SheetForm(
            title: String(localized: .solveTitle), confirm: model.startTitle, isDisabled: model.picked.isEmpty, note: model.setupNote,
            width: Theme.Size.solveSetup
        ) {
            if let line = model.resumeLine {
                FormRow(label: String(localized: .solveResume), detail: line) {
                    HStack(spacing: Theme.Space.s) {
                        Button(.solveResumeDrop) { model.dropResume() }.buttonStyle(.ghost)
                        Button(.solveResumeGo) { model.resume() }.buttonStyle(.prominent)
                    }
                }
            }
            FormRow(label: String(localized: .solveMode), detail: model.isMock ? String(localized: .solveModeMockDetail) : nil) {
                SegmentedControl(selection: $model.mode, options: model.modeOptions)
            }
            FormRow(label: String(localized: .solveFilter)) {
                SegmentedControl(selection: $model.pick.filter, options: model.filterOptions)
            }
            FormRow(label: String(localized: .solveUnit)) { Combobox(selection: $model.unit, options: model.unitOptions) }
            FormRow(label: String(localized: .solveSource)) { Select(selection: $model.source, options: model.sourceOptions) }
            FormRow(label: String(localized: .solveCount)) { Select(selection: $model.count, options: model.countOptions) }
            FormRow(label: String(localized: .solveOrder), last: true) {
                Select(selection: $model.pick.order, options: model.orderOptions)
            }
        } onConfirm: {
            model.start()
        }
    }
}
