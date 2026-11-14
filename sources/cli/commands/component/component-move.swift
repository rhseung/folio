import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

extension ComponentCommand {
    struct Move: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "move", abstract: String(localized: .componentMoveAbstract),
            discussion: String(localized: .componentMoveDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .componentMoveHelpComponent), valueName: "item"), completion: Complete.components)
        var component: String = ""
        @Flag(help: ArgumentHelp(String(localized: .componentMoveHelpUp))) var up = false
        @Flag(help: ArgumentHelp(String(localized: .componentMoveHelpDown))) var down = false

        func run() throws {
            guard up != down else { throw CLIError(exit: .usage, message: String(localized: .componentMoveUpOrDown)) }
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let (c, ref) = try r.split(component)
            let x = try r.component(ref, in: c)
            try perform(spec: ComponentMove(course: c.id, component: x.id, by: up ? -1 : 1), g, ctx: ctx)
        }
    }
}
