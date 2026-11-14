import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

extension ExamCommand {
    struct Scope: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .examScopeAbstract), discussion: String(localized: .examScopeDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpExam), valueName: "exam"), completion: Complete.exams) var exam: String =
            ""
        @Option(
            name: .customLong("unit"), help: ArgumentHelp(String(localized: .examScopeHelpUnits), valueName: "unit"),
            completion: Complete.units) var units: [String] = []
        @Flag(help: ArgumentHelp(String(localized: .examScopeHelpOff))) var off = false
        @Flag(help: ArgumentHelp(String(localized: .examScopeHelpTaught))) var taught = false

        func run() throws {
            guard !(taught && !units.isEmpty), !(taught && off) else {
                throw CLIError(exit: .usage, message: String(localized: .examScopeUnitOrTaught))
            }
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let (c, name) = try r.split(exam)
            let e = try r.exam(name, in: c)
            if taught {
                try perform(spec: ExamScopeTaught(course: c.id, exam: e.id), g, ctx: ctx)
                return
            }
            let ids = try r.many(units, from: c.file.units.map(\.title), what: "단원").map { try r.unit($0, in: c).id }
            try performAll(
                ids.map { ExamScope(course: c.id, exam: e.id, unit: $0, included: !off) }, g, ctx: ctx,
                done: off ? String(localized: .examScopeRemoved(ids.count)) : String(localized: .examScopeAdded(ids.count)))
        }
    }
}
