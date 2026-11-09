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

    /// Nil while the credits field is empty: there is no number to save yet.
    private var update: CourseSet? {
        credits.map {
            CourseSet(course: course.id, [.credits($0), .gradingMode(mode), .instructors(people), .categories(categories),
                                          .color(color), .icon(icon), .schedule(schedule), .reviews(reviews), .sharingApproved(sharingApproved)])
        }
    }

    /// Why the domain's rules refuse the draft, tried before saving rather than spelled out again here.
    private var refusal: String? { update.flatMap { workspace.refusal($0) } }

    var canSave: Bool { update != nil && folder != nil && refusal == nil }

    /// The folder name follows the title, main code and number, so saving a change to those renames it.
    var note: String? {
        guard let folder else { return String(localized: .courseEditNeedsFolder) }
        if let refusal { return refusal }
        let current = course.store.url.lastPathComponent
        return folder == current ? nil : String(localized: .courseEditRenames(current, folder))
    }

    private var scheduleUpdate: CourseSet { CourseSet(course: course.id, [.schedule(schedule)]) }

    var timesNote: String? { workspace.refusal(scheduleUpdate) }

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
        guard let update else { return false }
        let c = course.file.course
        if title != c.title || codes != c.codes || number != c.number {
            guard workspace.run(CourseRename(course: course.id, title: .changed(c.title, title), codes: .changed(c.codes, codes),
                                             number: .changed(c.number, number))) != nil else { return false }
        }
        workspace.run(update)
        return true
    }

    func confirmSchedule() {
        workspace.run(scheduleUpdate)
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
