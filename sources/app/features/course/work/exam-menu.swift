import FolioActions
import FolioDomain
import FolioStorage
import SwiftUI

struct ExamMenu: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.openLink) private var openLink
    @Environment(\.itemSheets) private var sheets
    let courseId: UUID
    let examId: UUID
    var host: MenuHost = .elsewhere
    var summary: UUID?? = nil

    var body: some View {
        if let exam = workspace.course(courseId)?.file.exams.first(where: { $0.id == examId }) {
            ItemMenu(
                source: ExamMenuSource(
                    workspace: workspace, courseId: courseId, exam: exam, host: host, summary: summary,
                    openLink: openLink, sheets: sheets))
        }
    }
}

extension Workspace {
    func examSummary(of exam: UUID, in courseId: UUID) -> UUID? {
        let notes = (try? course(courseId)?.store.notes()) ?? []
        return notes.first { $0.meta.kind == .examSummary && $0.meta.examId == exam }?.meta.id
    }
}
