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
        @Argument(help: ArgumentHelp(String(localized: .commonHelpItem), valueName: "item")) var item: String = ""
        @Flag(help: ArgumentHelp(String(localized: .examPlanCheckHelpUndo))) var undo = false

        func run() throws {
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let (c, name) = try r.split(exam)
            let i = try r.planItem(item, in: try r.exam(name, in: c), course: c)
            try perform(
                ExamPlanCheck(course: c.id, item: i.id, done: !undo), g, ctx: ctx,
                done: undo ? String(localized: .examPlanCheckUndone(i.title)) : String(localized: .examPlanCheckDone(i.title)))
        }
    }
}
