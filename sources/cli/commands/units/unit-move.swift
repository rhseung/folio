import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

extension UnitCommand {
    struct Move: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .unitMoveAbstract), discussion: String(localized: .unitMoveDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpUnit), valueName: "unit"), completion: Complete.units) var unit: String =
            ""
        @Flag(help: ArgumentHelp(String(localized: .unitMoveHelpUp))) var up = false
        @Flag(help: ArgumentHelp(String(localized: .unitMoveHelpDown))) var down = false
        @Option(help: ArgumentHelp(String(localized: .unitMoveHelpParent), valueName: "unit"), completion: Complete.units) var parent:
            String?
        @Flag(help: ArgumentHelp(String(localized: .unitMoveHelpTop))) var top = false

        func run() throws {
            guard [up, down, parent != nil, top].filter({ $0 }).count == 1 else {
                throw CLIError(exit: .usage, message: String(localized: .unitMoveOneDirection))
            }
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let (c, name) = try r.split(unit)
            let u = try r.unit(name, in: c)
            let target: UnitMove.Target = up ? .by(-1) : down ? .by(1) : .parent(try parent.map { try r.unit($0, in: c).id })
            try perform(spec: UnitMove(course: c.id, unit: u.id, target: target), g, ctx: ctx)
        }
    }
}
