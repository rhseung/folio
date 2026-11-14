import FolioDomain
import SwiftUI

struct ScreenView: View {
    let workspace: Workspace
    let entry: Navigator.Entry

    var body: some View {
        Group {
            switch Screen(entry) {
            case .today: TodayView(workspace: workspace)
            case .grades: GradesView(workspace: workspace)
            case .requirements: RequirementsView(workspace: workspace)
            case .people: PeopleView(workspace: workspace)
            case .codes: CodesView(workspace: workspace)
            case .settings: SettingsView(workspace: workspace)
            case .whatsNew: WhatsNewView(workspace: workspace)
            case .proposals: ProposalsView(workspace: workspace)
            case .semester(let id): SemesterView(workspace: workspace, semesterID: id).id(id)
            case .course(let id): CourseView(workspace: workspace, courseID: id).id(id)
            case .missing:
                ContentUnavailableView(String(localized: .linkNotFound(entry.link.string)), systemImage: "questionmark.folder")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.Palette.page)
            }
        }
        .environment(\.place, entry)
    }
}
