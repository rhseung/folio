import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

extension QuizCommand {
    struct Record: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .quizRecordAbstract), discussion: String(localized: .quizRecordDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpUnit), valueName: "unit"), completion: Complete.units) var unit: String
        @Argument(help: ArgumentHelp(String(localized: .commonHelpCard), valueName: "card")) var card: String
        @Argument(help: ArgumentHelp(String(localized: .commonHelpVerdict))) var verdict: Verdict
        @Option(help: ArgumentHelp(String(localized: .quizRecordHelpGrader))) var grader: QuizAttemptEvent.Grader = .self
        @Option(help: ArgumentHelp(String(localized: .quizRecordHelpAnswer), valueName: "answer")) var answer: String?

        func run() throws {
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let (c, name) = try r.split(unit)
            let u = try r.unit(name, in: c)
            let id = try r.card(card, unit: u, in: c).id
            try perform(
                spec: QuizRecord(course: c.id, attempt: QuizAttemptEvent(cardId: id, answer: answer, verdict: verdict, grader: grader)), g,
                ctx: ctx)
        }
    }
}
