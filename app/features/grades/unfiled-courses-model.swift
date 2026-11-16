import FolioActions
import FolioDomain
import SwiftUI

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
