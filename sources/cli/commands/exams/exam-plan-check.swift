import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

extension ExamCommand {
    struct PlanCheck: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "plan-check", abstract: String(localized: .examPlanCheckAbstract),
            discussion: String(localized: .examPlanCheckDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpExam), valueName: "exam"), completion: Complete.exams) var exam: String
        @Argument(help: ArgumentHelp(String(localized: .commonHelpItem), valueName: "items")) var items: [String] = []
        @Flag(help: ArgumentHelp(String(localized: .examPlanCheckHelpUndo))) var undo = false

        func run() throws {
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let (c, name) = try r.split(exam)
            let e = try r.exam(name, in: c)
            let picked = try r.many(items, from: e.plan.map { c.file.title(of: $0) }, what: ItemKind.examPlanItem.noun).map {
                try r.planItem($0, in: e, course: c)
            }
            let titles = picked.map { c.file.title(of: $0) }.joined(separator: ", ")
            try perform(
                ExamPlanCheck(course: c.id, items: picked.map(\.id), done: !undo), g, ctx: ctx,
                done: undo ? String(localized: .examPlanCheckUndone(titles)) : String(localized: .examPlanCheckDone(titles)))
        }
    }
}
