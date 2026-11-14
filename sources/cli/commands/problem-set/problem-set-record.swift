import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

extension ProblemSetCommand {
    struct Record: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .problemSetRecordAbstract), discussion: String(localized: .problemSetRecordDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .problemSetRecordHelpSet), valueName: "batch"), completion: Complete.problemSets)
        var set: String
        @Argument(help: ArgumentHelp(String(localized: .problemSetRecordHelpNumber), valueName: "number")) var number: String
        @Argument(help: ArgumentHelp(String(localized: .commonHelpVerdict))) var verdict: Verdict

        func run() throws {
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let (c, name) = try r.split(set)
            let s = try r.problemSet(name, in: c)
            guard s.problems.contains(where: { $0.number == number }) else {
                throw CLIError(exit: .notFound, message: String(localized: .problemSetRecordNotFound(number)))
            }
            try perform(
                spec: ProblemRecord(course: c.id, attempt: ProblemAttemptEvent(problemSetId: s.id, number: number, verdict: verdict)), g,
                ctx: ctx)
        }
    }
}
