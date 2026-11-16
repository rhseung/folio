import FolioActions
import FolioDomain
import SwiftUI

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
