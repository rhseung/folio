import FolioActions
import FolioDomain
import SwiftUI

@MainActor
struct CardMenuSource: ItemMenuSource {
    let workspace: Workspace
    let courseId: UUID
    let card: QuizCard
    var solveWrong: (() -> Void)?
    let sheets: ItemSheetsAction

    var commands: [CardMenuCommand] { CardMenuCommand.commands(solvesWrong: solveWrong != nil) }

    func row(_ command: CardMenuCommand) -> MenuRow {
        switch command {
        case .solveWrong:
            MenuRow(command, .quizStatsSolveUnitWrong, "arrow.counterclockwise", .action { solveWrong?() })
        case .edit:
            .edit(command) { sheets.present(.card(course: courseId, draft: CardDraft(card))) }
        case .share:
            .share(command, AppLink(.card, card.id), course: courseId)
        case .remove:
            .remove(command) { sheets.confirm(workspace.ask(QuizCardRemove(course: courseId, unit: card.unitId, card: card.id))) }
        }
    }
}

struct CardMenu: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.itemSheets) private var sheets
    let courseId: UUID
    let card: QuizCard
    var solveWrong: (() -> Void)?

    var body: some View {
        ItemMenu(source: CardMenuSource(workspace: workspace, courseId: courseId, card: card, solveWrong: solveWrong, sheets: sheets))
    }
}

@MainActor
struct ProblemSetMenuSource: ItemMenuSource {
    let workspace: Workspace
    let courseId: UUID
    let set: ProblemSet
    let openLink: OpenLinkAction
    let sheets: ItemSheetsAction

    private var file: CourseFile? { workspace.course(courseId)?.file }

    private func material(_ id: UUID?) -> FolioDomain.Material? {
        id.flatMap { id in file?.materials.first { $0.id == id } }
    }

    var commands: [ProblemSetMenuCommand] {
        ProblemSetMenuCommand.commands(hasSheet: material(set.materialId) != nil, hasSolution: material(set.solutionMaterialId) != nil)
    }

    func row(_ command: ProblemSetMenuCommand) -> MenuRow {
        switch command {
        case .openSheet:
            MenuRow(command, .quizProblemsOpenSheet, "doc.richtext", .action { open(set.materialId) })
        case .openSolution:
            MenuRow(command, .quizProblemsOpenSolution, "checkmark.seal", .action { open(set.solutionMaterialId) })
        case .share:
            .share(command, AppLink(.problemSet, set.id), course: courseId)
        case .remove:
            .remove(command) { sheets.confirm(workspace.ask(ProblemSetRemove(course: courseId, set: set.id))) }
        }
    }

    private func open(_ id: UUID?) {
        if let id { openLink(AppLink(.material, id), course: courseId) }
    }
}

struct ProblemSetMenu: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.openLink) private var openLink
    @Environment(\.itemSheets) private var sheets
    let courseId: UUID
    let set: ProblemSet

    var body: some View {
        ItemMenu(source: ProblemSetMenuSource(workspace: workspace, courseId: courseId, set: set, openLink: openLink, sheets: sheets))
    }
}

@MainActor
struct ProblemMenuSource: ItemMenuSource {
    let problem: ProblemSet.Problem
    let units: [FolioDomain.Unit]
    let correct: String
    let openSheet: (() -> Void)?
    let mark: (Verdict) -> Void
    let toggleUnit: (UUID) -> Void

    var commands: [ProblemMenuCommand] { ProblemMenuCommand.commands(hasSheet: openSheet != nil, hasUnits: !units.isEmpty) }

    func row(_ command: ProblemMenuCommand) -> MenuRow {
        switch command {
        case .openSheet:
            MenuRow(command, .quizProblemsOpenSheet, "doc.richtext", .action { openSheet?() })
        case .record:
            MenuRow(
                command, .quizProblemsRecord, "pencil.and.list.clipboard",
                .submenu([
                    MenuRow.Leaf(id: Verdict.correct, title: correct, symbol: "checkmark") { mark(.correct) },
                    MenuRow.Leaf(id: Verdict.partial, title: Verdict.partial.label, symbol: "questionmark") { mark(.partial) },
                    MenuRow.Leaf(id: Verdict.wrong, title: Verdict.wrong.label, symbol: "xmark") { mark(.wrong) },
                ]))
        case .units:
            MenuRow(
                command, .quizUnit, "list.bullet.indent",
                .submenu(
                    units.map { u in
                        MenuRow.Leaf(id: u.id, title: u.title, symbol: "list.bullet", checked: problem.unitIds.contains(u.id)) {
                            toggleUnit(u.id)
                        }
                    }))
        }
    }
}
