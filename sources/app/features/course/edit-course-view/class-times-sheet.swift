import FolioActions
import FolioDomain
import FolioStorage
import SwiftUI

struct ClassTimesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: EditCourseModel

    init(workspace: Workspace, course: LoadedCourse) {
        _model = State(initialValue: EditCourseModel(workspace: workspace, course: course))
    }

    var body: some View {
        SheetForm(
            title: model.course.title, confirm: String(localized: .commonSave), disabled: model.timesNote != nil,
            note: model.timesNote, carded: false, width: 600
        ) {
            ClassTimesBlock(schedule: $model.schedule)
        } onConfirm: {
            model.confirmSchedule()
            dismiss()
        }
    }
}
