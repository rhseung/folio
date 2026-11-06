import FolioDomain
import SwiftUI

/// The screen a link is drawn on. A window picks its screen here and nowhere else, and so will a pane (#62): the
/// switch over the link's kind has no default, so a new kind of link doesn't compile until it has a screen.
enum Screen: Hashable {
    case today, grades, requirements, people, codes, settings
    case semester(UUID)
    /// Everything a course holds opens in the course, which follows the link to its section and item.
    case course(UUID)
    /// The link names nothing in this folder any more (a course deleted since it was opened).
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
        case .semester: self = link.id.map(Screen.semester) ?? .missing
        case .course, .session, .unit, .note, .material, .assignment, .exam, .card, .problemSet:
            self = entry.course.map(Screen.course) ?? .missing
        }
    }

    /// The screen's own link, which the sidebar row for it opens.
    var link: AppLink? {
        switch self {
        case .today: .place(.today)
        case .grades: .place(.grades)
        case .requirements: .place(.requirements)
        case .people: .place(.people)
        case .codes: .place(.codes)
        case .settings: .place(.settings)
        case .semester(let id): AppLink(.semester, id)
        case .course(let id): .course(id)
        case .missing: nil
        }
    }
}

/// Draws one link, whatever holds it: the window's panel now, a pane with #62, an iPhone's whole screen (#134). A
/// screen gets the workspace and its link and nothing from the window around it: it opens other links through
/// `\.openLink`, takes the width it is given, and keeps its own tools in its own `PageBar`.
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
