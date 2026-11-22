import FolioDomain
import SwiftUI

struct SolveSetup: View {
    @Bindable var model: SolveModel
    @Environment(\.goBack) private var goBack
    @Environment(\.openLink) private var openLink

    var body: some View {
        SheetForm(
            title: String(localized: .solveTitle), confirm: model.startTitle, isDisabled: model.picked.isEmpty, note: model.setupNote,
            width: Theme.Size.solveSetup, onCancel: close
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
            FormRow(label: String(localized: .solveOrder), last: model.mode != .handwriting) {
                Select(selection: $model.pick.order, options: model.orderOptions)
            }
            // 문제집은 위에서 고른 문제로 만들므로 고르기 행 아래에 둔다.
            if model.mode == .handwriting { SolveCollectionRow(model: model) }
        } onConfirm: {
            model.start()
        }
    }

    func close() { model.close(goBack, openLink) }
}
