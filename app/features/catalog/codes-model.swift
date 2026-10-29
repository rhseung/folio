import Algorithms
import FolioActions
import FolioDomain
import Foundation
import Observation

@MainActor @Observable
final class CodesModel {
    let workspace: Workspace
    var query = ""
    var editing: UUID?

    init(workspace: Workspace) { self.workspace = workspace }

    /// Which courses use each code, so a tile can show them and a used code can't be removed.
    var users: [UUID: [UUID]] {
        Dictionary(grouping: workspace.allCourseRecords.flatMap { c in c.codes.map { (code: $0, course: c.id) } }, by: \.code)
            .mapValues { $0.map(\.course) }
    }

    func programs(in catalog: Catalog) -> [String] { Array(catalog.codes.map(\.program).uniqued()) }

    func subtitle(_ catalog: Catalog) -> String { String(localized: .codesSubtitle(catalog.codes.count)) }

    func shown(_ program: String, in catalog: Catalog) -> [CourseCode] {
        catalog.codes.filter { $0.program == program && matches($0) }.sorted { $0.prefix < $1.prefix }
    }

    /// While searching, a program with no match is hidden rather than shown empty.
    func showsProgram(_ program: String, in catalog: Catalog) -> Bool { query.isEmpty || !shown(program, in: catalog).isEmpty }

    func hasNoMatch(in catalog: Catalog) -> Bool { !query.isEmpty && !catalog.codes.contains(where: matches) }

    func add(_ program: String, to catalog: inout Catalog) {
        let code = CourseCode(device: workspace.device, at: .now, prefix: "", program: program)
        catalog.codes.append(code)
        editing = code.id
    }

    func remove(_ id: UUID, from catalog: inout Catalog) {
        editing = nil
        catalog.codes.removeAll { $0.id == id }
    }

    /// Why the code can't be removed (a course still uses it), or nil.
    func removal(_ id: UUID) -> String? {
        var c = workspace.catalog
        c.codes.removeAll { $0.id == id }
        return workspace.refusal(CatalogSet(catalog: c))
    }

    /// A code added and left blank goes away with its editor, instead of staying in catalog.json as an empty tile.
    func closeEditor(_ id: UUID, catalog: inout Catalog) {
        guard editing == id else { return }
        editing = nil
        if let code = catalog.codes.first(where: { $0.id == id }), users[id] == nil,
           code.prefix.trimmingCharacters(in: .whitespaces).isEmpty, code.department.trimmingCharacters(in: .whitespaces).isEmpty {
            catalog.codes.removeAll { $0.id == id }
        }
    }

    /// Newest term first, the way the sidebar lists semesters.
    func courses(using ids: [UUID]) -> [Course] {
        workspace.allCourseRecords.filter { ids.contains($0.id) }
            .sorted { (workspace.semester(of: $0)?.order ?? 0, $1.title) > (workspace.semester(of: $1)?.order ?? 0, $0.title) }
    }

    static func programTitle(_ program: String) -> String { program.isEmpty ? String(localized: .codesNoProgram) : program }

    static func tileFooter(_ code: CourseCode, courses: Int) -> String {
        courses == 0 ? code.source : String(localized: .codesCourseCount(courses)) + (code.source.isEmpty ? "" : " · \(code.source)")
    }

    private func matches(_ c: CourseCode) -> Bool {
        query.isEmpty || [c.prefix, c.department].contains { $0.localizedCaseInsensitiveContains(query) }
    }
}
