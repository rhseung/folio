import FolioDomain
import Foundation
import Observation

/// The courses each person taught are found from the courses' instructorIds, never stored on the person.
@MainActor @Observable
final class PeopleModel {
    let workspace: Workspace
    var query = ""
    var selection: UUID?
    var removing: Person?

    init(workspace: Workspace) { self.workspace = workspace }

    /// A chosen person removed elsewhere (another device's save) falls back to the first instead of an empty page.
    func shown(in catalog: Catalog) -> UUID? {
        selection.flatMap { id in catalog.people.contains { $0.id == id } ? id : nil }
            ?? catalog.people.min(by: Self.listOrder)?.id
    }

    func groups(in catalog: Catalog) -> [(role: PersonRole, people: [Person])] {
        let people = catalog.people
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.email.localizedCaseInsensitiveContains(query) }
            .sorted(by: Self.listOrder)
        return PersonRole.allCases.compactMap { role in
            let group = people.filter { $0.role == role }
            return group.isEmpty ? nil : (role, group)
        }
    }

    var emptyList: String { String(localized: query.isEmpty ? .peopleEmpty : .peopleNoMatch) }

    var taughtCount: [UUID: Int] {
        Dictionary(workspace.allCourseRecords.flatMap(\.instructorIds).map { ($0, 1) }, uniquingKeysWith: +)
    }

    func taught(by id: UUID) -> [(course: Course, semester: Semester?)] {
        workspace.allCourseRecords.filter { $0.instructorIds.contains(id) }
            .map { (course: $0, semester: workspace.semester(of: $0)) }
            .sorted { ($0.semester?.order ?? 0, $1.course.title) > ($1.semester?.order ?? 0, $0.course.title) }
    }

    func name(_ p: Person) -> String { p.name.isEmpty ? String(localized: .peopleUnnamed) : p.name }

    func subtitle(_ p: Person) -> String {
        let n = taught(by: p.id).count
        return ([p.role.label] + (n == 0 ? [] : [String(localized: .peopleTaughtCount(n))])).joined(separator: " · ")
    }

    func removalMessage(_ p: Person) -> String {
        let n = taught(by: p.id).count
        return String(localized: n == 0 ? .peopleRemoveNoCourses : .peopleRemoveCourses(n))
    }

    /// A course kept only in the transcript has no folder, so it has no page to open.
    func opens(_ course: UUID) -> Bool { workspace.course(course) != nil }

    func add(to catalog: inout Catalog) {
        let person = Person(device: workspace.device, at: .now, name: String(localized: .peopleNewName))
        catalog.people.append(person)
        selection = person.id
        query = ""
    }

    func remove(_ person: Person, from catalog: inout Catalog) {
        catalog.people.removeAll { $0.id == person.id }
        selection = nil
    }

    private static func listOrder(_ a: Person, _ b: Person) -> Bool { (a.role.order, a.name) < (b.role.order, b.name) }
}

extension PersonRole: CaseIterable {
    public static let allCases: [PersonRole] = [.professor, .lecturer, .assistant]

    var label: String {
        switch self {
        case .professor: String(localized: .roleProfessor)
        case .lecturer: String(localized: .roleLecturer)
        case .assistant: String(localized: .roleAssistant)
        }
    }

    var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}
