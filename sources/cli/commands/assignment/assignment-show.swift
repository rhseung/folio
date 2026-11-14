import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

extension AssignmentCommand {
    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .assignmentShowAbstract), discussion: String(localized: .assignmentShowDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(
            help: ArgumentHelp(String(localized: .assignmentShowHelpAssignment), valueName: "assignment"), completion: Complete.assignments)
        var assignment: String = ""

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let (c, name) = try r.split(assignment)
            let a = try r.assignment(name, in: c)
            if g.json { return try printJSON(a) }
            let f = c.file
            courseHeader(c, catalog: try? r.ctx.catalog())
            say(a.title.styled(.bold))
            if let due = a.due { say(String(localized: .assignmentShowDue(when(due, now: r.ctx.now, time: true)))) }
            say(String(localized: .assignmentShowStatus(a.status.rawValue.toned)))
            if let repeats = a.repeats { say(String(localized: .assignmentShowRepeats(repeats.label))) }
            if !a.memo.isEmpty { say(String(localized: .assignmentShowMemo(a.memo))) }
            let scores = f.scores.filter { $0.assignmentId == a.id }
            if !scores.isEmpty {
                say(String(localized: .assignmentShowScores))
                for s in scores {
                    let comp = f.components.first { $0.id == s.componentId }?.name ?? ""
                    say("    \(comp)  \(GradesLock.masked("\(s.score.formatted())/\(s.max.formatted())"))")
                }
            }
        }
    }
}
