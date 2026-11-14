import FolioActions
import FolioDomain
import FolioStorage
import SwiftUI

@MainActor
struct ExamMenuSource: ItemMenuSource {
    let workspace: Workspace
    let courseId: UUID
    let exam: Exam
    let host: MenuHost
    var summary: UUID?? = nil
    let openLink: OpenLinkAction
    let sheets: ItemSheetsAction

    private var link: AppLink { AppLink(.exam, exam.id) }

    var commands: [ExamMenuCommand] {
        workspace.course(courseId)?.file.commands(for: exam, host: host) ?? []
    }

    func row(_ command: ExamMenuCommand) -> MenuRow {
        switch command {
        case .open:
            .open(command) { openLink(link, course: courseId) }
        case .summary:
            MenuRow(command, hasSummary ? .examsSummaryOpen : .examsSummaryMake, "doc.text", .action(openSummary))
        case .addFiles:
            MenuRow(
                command, .menuAddFilesEllipsis, "doc.badge.plus",
                .action {
                    if let folder = MaterialIntake.folder(of: exam) { sheets.addFiles(FileIntake(course: courseId, folder: folder)) }
                })
        case .edit:
            .edit(command) { sheets.present(.exam(course: courseId, exam: exam.id)) }
        case .share:
            .share(command, link, course: courseId)
        case .remove:
            .remove(command) { sheets.confirm(workspace.ask(ExamRemove(course: courseId, exam: exam.id))) }
        }
    }

    private var hasSummary: Bool {
        if let summary { return summary != nil }
        return workspace.examSummary(of: exam.id, in: courseId) != nil
    }

    private func openSummary() {
        if let id = workspace.run(ExamSummary(course: courseId, exam: exam.id))?.made { openLink(AppLink(.note, id), course: courseId) }
    }
}

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

struct PlanItemMenu: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.itemSheets) private var sheets
    let courseId: UUID
    let examId: UUID
    let item: UUID
    let done: Bool
    let toggle: () -> Void

    var body: some View {
        ItemMenu(
            source: PlanItemMenuSource(
                workspace: workspace, courseId: courseId, examId: examId, item: item, done: done, toggle: toggle, sheets: sheets))
    }
}

@MainActor
struct PlanItemMenuSource: ItemMenuSource {
    let workspace: Workspace
    let courseId: UUID
    let examId: UUID
    let item: UUID
    let done: Bool
    let toggle: () -> Void
    let sheets: ItemSheetsAction

    var commands: [PlanItemMenuCommand] { ExamPlanItem.commands(done: done) }

    func row(_ command: PlanItemMenuCommand) -> MenuRow {
        switch command {
        case .done(let on):
            MenuRow(command, .menuDone, "checkmark.circle", .check(on) { _ in toggle() })
        case .remove:
            .remove(command) { sheets.confirm(workspace.ask(ExamPlanRemove(course: courseId, exam: examId, item: item))) }
        }
    }
}
