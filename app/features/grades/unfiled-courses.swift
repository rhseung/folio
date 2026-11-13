import FolioActions
import FolioDomain
import SwiftUI

/// Courses schema v1 kept in transcript.json without a folder. They count nowhere until moved, so the notice stays
/// until the user moves them; a credited term without a source refuses, and the refusal says so.
@MainActor @Observable
final class UnfiledCoursesModel {
    let workspace: Workspace

    init(workspace: Workspace) { self.workspace = workspace }

    var courses: [Course] { workspace.transcript.unfiledCourses }

    func detail(_ course: Course) -> String {
        let semester = workspace.semester(of: course)
        return [semester?.title ?? "", String(localized: .semesterCredits(course.credits.formatted()))].filter { !$0.isEmpty }.joined(
            separator: " · ")
    }

    var refusal: String? { workspace.refusal(TranscriptMove()) }

    var confirmation: String { workspace.confirmation(TranscriptMove()) ?? "" }

    func move() { workspace.run(TranscriptMove()) }
}

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
