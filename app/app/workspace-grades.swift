import FolioActions
import FolioDomain
import FolioStorage
import Foundation

extension Workspace {

    /// Categories of undeclared programs stay in catalog.json but out of every requirement view.
    /// `EC 주전공`, `AI 복수전공`.
    func programTitle(_ program: StudentProgram) -> String {
        (catalog.codes.first { $0.id == program.codeId }?.prefix ?? "?") + " " + program.kind.label
    }

    var requirementCatalog: Catalog { catalog.scoped(to: transcript.graduation.programs) }

    /// A draft in the default mail app. mailto can't choose the sending account; the mail app's default account does.
    func mailURL(to address: String) -> URL? {
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = address
        return address.isEmpty ? nil : c.url
    }

    func saveGraduation(_ rule: GraduationRule) {
        run(GraduationSet(rule: rule))
    }

    func setCategories(_ courseId: UUID, _ ids: [UUID]) {
        run(CourseSet(course: courseId, [.categories(ids)]))
    }

    func approveSharing(_ courseId: UUID) {
        run(CourseSet(course: courseId, [.sharingApproved(true)]))
    }
}
