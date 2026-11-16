import FolioActions
import FolioDomain
import SwiftUI

struct UnfiledCoursesNotice: View {
    @State private var model: UnfiledCoursesModel
    @State private var confirming = false

    init(workspace: Workspace) {
        _model = State(initialValue: UnfiledCoursesModel(workspace: workspace))
    }

    var body: some View {
        let courses = model.courses
        if !courses.isEmpty {
            NoticeCard(
                title: String(localized: .unfiledTitle(courses.count)), detail: model.refusal ?? String(localized: .unfiledDetail),
                systemImage: "folder.badge.questionmark"
            ) {
                Button(.unfiledMoveEllipsis) { confirming = true }.buttonStyle(.pointing(.bordered)).disabled(model.refusal != nil)
            } rows: {
                ForEach(Array(courses.enumerated()), id: \.element.id) { i, course in
                    CardRow(last: i == courses.count - 1) {
                        Text(course.title).lineLimit(1)
                        Spacer()
                        Text(model.detail(course)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                    }
                }
            }
            .confirmationDialog(model.confirmation, isPresented: $confirming) {
                Button(.unfiledMove) { model.move() }
            } message: {
                Text(.unfiledConfirmMessage)
            }
        }
    }
}
