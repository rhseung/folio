import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

extension QuizCommand {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .quizListAbstract), discussion: String(localized: .quizListDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpCourse), valueName: "course"), completion: .custom(Complete.courses))
        var course: String = ""
        @Option(help: ArgumentHelp(String(localized: .quizListHelpUnit), valueName: "unit"), completion: Complete.units) var unit: String?
        @Flag(help: ArgumentHelp(String(localized: .commonHelpLines))) var lines = false

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let c = try r.course(course)
            let store = c.store
            let units = try unit.map { [try r.unit(c.local($0), in: c)] } ?? c.file.units
            let decks = try units.map { ($0, try store.loadQuiz(unit: $0.id).model.cards) }.filter { !$0.1.isEmpty }
            if g.json { return try printJSON(decks.flatMap(\.1)) }
            if lines {
                for (u, cards) in decks { for card in cards { line([card.id.uuidString, u.title, card.type.rawValue, card.prompt]) } }
                return
            }
            courseHeader(c, catalog: try? r.ctx.catalog())
            var t = Table(
                header: [
                    String(localized: .quizListHeaderUnit), String(localized: .quizListHeaderKind),
                    String(localized: .quizListHeaderCategory), String(localized: .quizListHeaderPrompt),
                ], shrink: [3])
            for (u, cards) in decks {
                for card in cards { t.rows.append([u.title, card.type.rawValue, card.category.rawValue, card.prompt]) }
            }
            t.print()
            footer(decks.map(\.1.count).reduce(0, +))
        }
    }
}
