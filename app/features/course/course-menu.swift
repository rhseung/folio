import FolioDomain
import SwiftUI

/// A course's menu, the same on its sidebar row, the semester page's card and its own page's `⋯` (#403).
@MainActor
struct CourseMenuSource: ItemMenuSource {
    let workspace: Workspace
    let courseId: UUID
    let host: MenuHost
    let openLink: OpenLinkAction
    let sheets: ItemSheetsAction

    private var course: LoadedCourse? { workspace.course(courseId) }

    /// Among the sidebar's courses of its term, in the order the sidebar keeps.
    private var siblings: (semester: Semester, ids: [UUID])? {
        guard let course, let semester = workspace.semester(of: course.file.course) else { return nil }
        return (semester, workspace.sidebarCourses(in: semester).map(\.id))
    }

    private var ongoing: Session? {
        workspace.ongoingClass(at: workspace.liveNow).flatMap { $0.courseId == courseId ? $0.session : nil }
    }

    var commands: [CourseMenuCommand] {
        #if os(macOS)
        let finder = true
        #else
        let finder = false
        #endif
        let order = siblings.flatMap { s in s.ids.firstIndex(of: courseId).map { (index: $0, count: s.ids.count) } }
        return CourseMenuCommand.commands(host: host, recordable: ongoing != nil, order: order, finder: finder)
    }

    func row(_ command: CourseMenuCommand) -> MenuRow {
        switch command {
        case .open:
            .open(command) { openLink(.course(courseId), course: courseId) }
        case .record:
            MenuRow(command, .sessionsRecord, "record.circle", disabled: workspace.recorder.isActive, .action {
                if let ongoing { workspace.record(ongoing.id, in: courseId) }
            })
        case .edit:
            .edit(command) { sheets.present(.course(courseId)) }
        case .moveUp:
            MenuRow(command, .unitsMoveUp, "arrow.up", .action { move(by: -1) })
        case .moveDown:
            MenuRow(command, .unitsMoveDown, "arrow.down", .action { move(by: 1) })
        case .share:
            .share(command, .course(courseId), course: courseId)
        case .showInFinder:
            MenuRow(command, .commonShowInFinder, "folder", .action { if let url = course?.store.url { revealInFinder(url) } })
        }
    }

    /// As the list's drag does: the destination is the gap the course lands before.
    private func move(by offset: Int) {
        guard let siblings, let i = siblings.ids.firstIndex(of: courseId) else { return }
        workspace.moveSidebarCourses(in: siblings.semester, from: [i], to: offset < 0 ? i - 1 : i + 2)
    }
}

struct CourseMenu: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.openLink) private var openLink
    @Environment(\.itemSheets) private var sheets
    let courseId: UUID
    var host: MenuHost = .elsewhere

    var body: some View {
        ItemMenu(source: CourseMenuSource(workspace: workspace, courseId: courseId, host: host, openLink: openLink, sheets: sheets))
    }
}

/// A term's page is its editor, so its menu has no 편집….
@MainActor
struct SemesterMenuSource: ItemMenuSource {
    let semesterId: UUID
    let host: MenuHost
    /// Where the screen can add a course to this term.
    var addCourse: (@MainActor () -> Void)?
    /// The sidebar's fold: whether the term shows its courses now, and the way to flip it. Nil without courses.
    var folded: Bool?
    var fold: (@MainActor () -> Void)?
    let openLink: OpenLinkAction

    var commands: [SemesterMenuCommand] { SemesterMenuCommand.commands(host: host, addsCourse: addCourse != nil, folded: folded) }

    func row(_ command: SemesterMenuCommand) -> MenuRow {
        switch command {
        case .open:
            .open(command) { openLink(AppLink(.semester, semesterId)) }
        case .addCourse:
            MenuRow(command, .rootAddCourse, "plus", .action { addCourse?() })
        case .fold(let open):
            MenuRow(command, open ? .commonCollapse : .commonExpand, open ? "chevron.up" : "chevron.down", .action { fold?() })
        case .share:
            .share(command, AppLink(.semester, semesterId), course: nil)
        }
    }
}

struct SemesterMenu: View {
    @Environment(\.openLink) private var openLink
    let semesterId: UUID
    var host: MenuHost = .elsewhere
    var addCourse: (@MainActor () -> Void)?
    var folded: Bool?
    var fold: (@MainActor () -> Void)?

    var body: some View {
        ItemMenu(source: SemesterMenuSource(semesterId: semesterId, host: host, addCourse: addCourse, folded: folded, fold: fold, openLink: openLink))
    }
}
