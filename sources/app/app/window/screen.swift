import FolioDomain
import SwiftUI

enum Screen: Hashable {
    case today, grades, requirements, people, codes, settings, whatsNew, proposals
    case semester(UUID)
    case course(UUID)
    case missing

    init(_ entry: Navigator.Entry) {
        let link = entry.link
        switch link.kind {
        case .today: self = .today
        case .grades: self = .grades
        case .requirements: self = .requirements
        case .people, .person: self = .people
        case .codes: self = .codes
        case .settings: self = .settings
        case .whatsNew: self = .whatsNew
        case .proposals: self = .proposals
        case .semester: self = link.id.map(Screen.semester) ?? .missing
        case .course, .session, .unit, .note, .material, .assignment, .exam, .card, .problemSet, .recording:
            self = entry.course.map(Screen.course) ?? .missing
        }
    }

    var link: AppLink? {
        switch self {
        case .today: .place(.today)
        case .grades: .place(.grades)
        case .requirements: .place(.requirements)
        case .people: .place(.people)
        case .codes: .place(.codes)
        case .settings: .place(.settings)
        case .whatsNew: .place(.whatsNew)
        case .proposals: .place(.proposals)
        case .semester(let id): AppLink(.semester, id)
        case .course(let id): .course(id)
        case .missing: nil
        }
    }
}

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
