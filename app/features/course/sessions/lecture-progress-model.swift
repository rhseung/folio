import FolioDomain
import Foundation
import Observation

/// One lecture file's progress: which classes went through which pages, and what no class has reached yet.
@MainActor @Observable
final class LectureProgressModel {
    struct Row: Identifiable, Equatable {
        var id: Int { firstPage }
        let firstPage: Int
        let lastPage: Int
        let pages: String
        /// Empty for pages no class has reached.
        let classes: [Class]
    }

    struct Class: Identifiable, Equatable {
        let id: UUID
        let day: String
        var link: AppLink { AppLink(.session, id) }
    }

    let workspace: Workspace
    let courseId: UUID
    let materialId: UUID
    private(set) var pageCount: Int?

    init(workspace: Workspace, course: UUID, material: UUID) {
        self.workspace = workspace
        courseId = course
        materialId = material
    }

    private var file: CourseFile? { workspace.course(courseId)?.file }
    private var material: FolioDomain.Material? { file?.materials.first { $0.id == materialId } }

    func load() async {
        guard let material else { return }
        pageCount = await workspace.pageCount(of: material, course: courseId)
    }

    var rows: [Row] {
        guard let file else { return [] }
        return file.lectureProgress(of: materialId, pageCount: pageCount).map { span in
            let classes = span.sessions.compactMap { id in file.sessions.first { $0.id == id } }
                .map { Class(id: $0.id, day: file.day(of: $0, calendar: workspace.calendar)) }
            return Row(firstPage: span.firstPage, lastPage: span.lastPage,
                       pages: span.firstPage == span.lastPage ? "p.\(span.firstPage)" : "p.\(span.firstPage)–\(span.lastPage)",
                       classes: classes)
        }
    }

    /// `40쪽 중 28쪽 나감`, or without a count only how many pages classes went through.
    var summary: String? {
        let covered = rows.filter { !$0.classes.isEmpty }.reduce(0) { $0 + $1.lastPage - $1.firstPage + 1 }
        guard covered > 0 || pageCount != nil else { return nil }
        if let pageCount { return String(localized: .materialsProgressSummary(pageCount, covered)) }
        return String(localized: .materialsProgressCovered(covered))
    }

    /// Classes that used the file without saying which pages.
    var unranged: String? {
        guard let file else { return nil }
        let days = file.unrangedSessions(of: materialId).map { file.day(of: $0, calendar: workspace.calendar) }
        return days.isEmpty ? nil : String(localized: .materialsProgressUnranged(days.joined(separator: " · ")))
    }
}
