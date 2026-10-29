import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

struct UnitCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "unit", abstract: String(localized: .unitAbstract),
        subcommands: [List.self, Show.self] + GeneratedCommands.unit + [Move.self])

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .unitListAbstract), discussion: String(localized: .unitListDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .unitListHelpCourse), valueName: "course"), completion: .custom(Complete.courses)) var course: String = ""
        @Option(help: ArgumentHelp(String(localized: .unitListHelpDepth), valueName: "depth")) var depth: Int?
        @Flag(help: ArgumentHelp(String(localized: .commonHelpLines))) var lines = false

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let c = try r.course(course)
            let f = try c.requireFile()
            let outline = UnitTree.outline(f.units).filter { item in depth.map { item.depth < $0 } ?? true }
            if g.json { return try printJSON(outline.map(\.unit)) }
            if lines {
                for (u, _) in outline { line(["\(c.code)/\(u.title)", u.title, String(localized: .unitListSessions(u.sessionIds.count))]) }
                return
            }
            courseHeader(c, catalog: try? r.ctx.catalog())
            for (i, item) in outline.enumerated() {
                say(treePrefix(outline.map(\.depth), at: i) + item.unit.title + (item.unit.sessionIds.isEmpty ? "" : String(localized: .unitListSessionsIndented(item.unit.sessionIds.count)).styled(.dim)))
            }
            footer(outline.count)
        }
    }

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .unitShowAbstract), discussion: String(localized: .unitShowDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .unitShowHelpUnit), valueName: "unit"), completion: Complete.units) var unit: String = ""

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let (c, name) = try r.split(unit)
            let u = try r.unit(name, in: c)
            if g.json { return try printJSON(u) }
            let f = try c.requireFile()
            courseHeader(c, catalog: try? r.ctx.catalog())
            say(u.title.styled(.bold))
            if let parent = u.parentId.flatMap({ id in f.units.first { $0.id == id } }) { say(String(localized: .unitShowParent(parent.title))) }
            let children = f.units.filter { $0.parentId == u.id }.sorted { $0.order < $1.order }
            for (title, names) in [(String(localized: .unitShowChildren), children.map(\.title)),
                                   (String(localized: .unitShowSessions), u.sessionIds.compactMap { id in f.sessions.first { $0.id == id }.map { f.name(of: $0) } }),
                                   (String(localized: .unitShowExams), u.examIds.compactMap { id in f.exams.first { $0.id == id }?.title })] where !names.isEmpty {
                say("  \(title)")
                for n in names { say("    \(n)") }
            }
        }
    }

    struct Move: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .unitMoveAbstract), discussion: String(localized: .unitMoveDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpUnit), valueName: "unit"), completion: Complete.units) var unit: String = ""
        @Flag(help: ArgumentHelp(String(localized: .unitMoveHelpUp))) var up = false
        @Flag(help: ArgumentHelp(String(localized: .unitMoveHelpDown))) var down = false
        @Option(help: ArgumentHelp(String(localized: .unitMoveHelpParent), valueName: "unit"), completion: Complete.units) var parent: String?
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

/// `├─ `, `└─ ` and `│  ` for item `i` of an outline given as depths.
func treePrefix(_ depths: [Int], at i: Int) -> String {
    let d = depths[i]
    guard d > 0 else { return "" }
    // Whether another sibling at `level` follows before the tree climbs above it.
    func continues(_ level: Int) -> Bool {
        for j in (i + 1)..<depths.count {
            if depths[j] < level { return false }
            if depths[j] == level { return true }
        }
        return false
    }
    return (1..<d).map { continues($0) ? "│  " : "   " }.joined() + (continues(d) ? "├─ " : "└─ ")
}

/// One action per item on a shared context, so the command prints one result (and one JSON value) for all of them.
func performAll<A: Action>(_ actions: [A], _ options: GlobalOptions, ctx: ActionContext, done: String) throws {
    for a in actions.dropLast() {
        do {
            try a.run(ctx)
        } catch let e as ActionError {
            switch e {
            case .notFound(let m): throw CLIError(exit: .notFound, message: m)
            case .rule(let m): throw CLIError(exit: .rule, message: m)
            case .conflict(let m): throw CLIError(exit: .conflict, message: m)
            }
        }
    }
    try perform(actions[actions.count - 1], options, ctx: ctx, done: done)
}
