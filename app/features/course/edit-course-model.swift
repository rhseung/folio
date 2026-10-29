import FolioActions
import FolioDomain
import Foundation
import Observation

/// The draft of course.json behind the edit sheet and the class-times sheet.
@MainActor @Observable
final class EditCourseModel {
    let workspace: Workspace
    let course: LoadedCourse
    var title: String
    var codes: [UUID]
    var number: String
    var credits: Double?
    var mode: GradingMode
    var people: [UUID]
    var categories: [UUID]
    var color: String
    var icon: String?
    var reviews: Bool
    var sharingApproved: Bool
    var schedule: [ClassTime]

    init(workspace: Workspace, course: LoadedCourse) {
        self.workspace = workspace
        self.course = course
        let c = course.file.course
        title = c.title
        codes = c.codes
        number = c.number
        credits = c.credits
        mode = c.gradingMode
        people = c.instructorIds
        categories = c.categoryIds
        color = c.color
        icon = c.icon
        reviews = c.reviews != false
        sharingApproved = c.sharingApproved == true
        schedule = c.schedule
    }

    /// The course as the form now has it, for what its codes and approval let it share.
    var draft: Course {
        var c = course.file.course
        c.codes = codes
        c.sharingApproved = sharingApproved ? true : nil
        return c
    }

    var folder: String? { workspace.folderName(title: title, codes: codes, number: number) }

    var badTime: Bool { schedule.contains { $0.endMinute <= $0.startMinute } }

    var canSave: Bool { (credits ?? -1) >= 0 && folder != nil && !badTime }

    /// The folder name follows the title, main code and number, so saving a change to those renames it.
    var note: String? {
        guard let folder else { return String(localized: .courseEditNeedsFolder) }
        if badTime { return String(localized: .classTimesBadTime) }
        let current = course.store.url.lastPathComponent
        return folder == current ? nil : String(localized: .courseEditRenames(current, folder))
    }

    var timesNote: String? { badTime ? String(localized: .classTimesBadTime) : nil }

    var codeDetail: String? { codes.count > 1 ? String(localized: .courseEditCrossListed) : nil }

    var codeOptions: [(UUID, String)] {
        codes.map { id in (id, workspace.catalog.codes.first { $0.id == id }?.prefix ?? "?") }
    }

    func makeMain(_ id: UUID) {
        codes.removeAll { $0 == id }
        codes.insert(id, at: 0)
    }

    var peopleOptions: [PickOption<UUID>] {
        workspace.catalog.people.sorted { $0.name < $1.name }.map {
            PickOption(id: $0.id, title: $0.name, detail: [$0.role.label, $0.email].filter { !$0.isEmpty }.joined(separator: " · "))
        }
    }

    var peoplePlaceholder: String {
        workspace.catalog.people.isEmpty ? String(localized: .courseEditAddPeopleFirst) : String(localized: .designPick)
    }

    var showsSharing: Bool { workspace.requirementCatalog.categories.contains { $0.maxSharedCredits != nil } }

    func confirm() -> Bool {
        guard let credits else { return false }
        let c = course.file.course
        if title != c.title || codes != c.codes || number != c.number {
            guard workspace.run(CourseRename(course: course.id, title: title, codes: codes, number: number)) != nil else { return false }
        }
        workspace.run(CourseSet(course: course.id, [.credits(credits), .gradingMode(mode), .instructors(people), .categories(categories),
                                                   .color(color), .icon(icon), .schedule(schedule), .reviews(reviews), .sharingApproved(sharingApproved)]))
        return true
    }

    func confirmSchedule() {
        workspace.run(CourseSet(course: course.id, [.schedule(schedule)]))
    }
}

/// People, memo and folder at the bottom of the course overview.
@MainActor @Observable
final class CourseInfoModel {
    let workspace: Workspace
    var memo = ""

    init(workspace: Workspace) { self.workspace = workspace }

    func people(_ course: Course) -> [Person] {
        course.instructorIds.compactMap { id in workspace.catalog.people.first { $0.id == id } }
    }

    func detail(_ p: Person) -> String? {
        [p.office, p.officeHours].filter { !$0.isEmpty }.joined(separator: " · ").nilIfEmpty
    }

    func mailURL(_ p: Person) -> URL? { workspace.mailURL(to: p.email) }

    func saveMemo(_ courseId: UUID) {
        workspace.run(CourseSet(course: courseId, [.memo(memo)]))
    }
}
