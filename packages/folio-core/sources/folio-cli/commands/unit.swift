import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

struct UnitCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "unit", abstract: "단원: 트리, 추가, 옮기기, 회차 연결",
        subcommands: [List.self, Show.self] + GeneratedCommands.unit + [Move.self])

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "과목의 단원 트리", discussion: """
            예시:
              folio unit list EC4207             그래프 이론의 단원 트리
              folio unit list EC4207 --depth 1   맨 위 단원만
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("과목. 강의 코드, 폴더 이름, 과목 이름, UUID", valueName: "course"), completion: .custom(Complete.courses)) var course: String = ""
        @Option(help: ArgumentHelp("보여 줄 깊이. 1이면 맨 위 단원만", valueName: "depth")) var depth: Int?
        @Flag(help: "머리글 없이 한 줄에 하나, 탭으로 나눠서") var lines = false

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let c = try r.course(course)
            let f = try c.requireFile()
            let outline = UnitTree.outline(f.units).filter { item in depth.map { item.depth < $0 } ?? true }
            if g.json { return try printJSON(outline.map(\.unit)) }
            if lines {
                for (u, _) in outline { line(["\(c.code)/\(u.title)", u.title, "\(u.sessionIds.count)회차"]) }
                return
            }
            courseHeader(c, catalog: try? r.ctx.catalog())
            for (i, item) in outline.enumerated() {
                say(treePrefix(outline.map(\.depth), at: i) + item.unit.title + (item.unit.sessionIds.isEmpty ? "" : "  \(item.unit.sessionIds.count)회차".styled(.dim)))
            }
            footer(outline.count)
        }
    }

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "단원 하나의 자세한 내용", discussion: """
            예시:
              folio unit show EC4207/트리
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("<과목>/<단원>. 예: EC4207/트리", valueName: "unit"), completion: Complete.units) var unit: String = ""

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let (c, name) = try r.split(unit)
            let u = try r.unit(name, in: c)
            if g.json { return try printJSON(u) }
            let f = try c.requireFile()
            courseHeader(c, catalog: try? r.ctx.catalog())
            say(u.title.styled(.bold))
            if let parent = u.parentId.flatMap({ id in f.units.first { $0.id == id } }) { say("  상위  \(parent.title)") }
            let children = f.units.filter { $0.parentId == u.id }.sorted { $0.order < $1.order }
            for (title, names) in [("하위 단원", children.map(\.title)),
                                   ("회차", u.sessionIds.compactMap { id in f.sessions.first { $0.id == id }.map { f.name(of: $0) } }),
                                   ("시험", u.examIds.compactMap { id in f.exams.first { $0.id == id }?.title })] where !names.isEmpty {
                say("  \(title)")
                for n in names { say("    \(n)") }
            }
        }
    }

    struct Move: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "단원을 형제 사이에서 옮기거나 다른 단원 아래로 옮기기", discussion: """
            예시:
              folio unit move EC4207/트리 --up
              folio unit move EC4207/"스패닝 트리" --parent 그래프
              folio unit move EC4207/"스패닝 트리" --top
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("<과목>/<단원>", valueName: "unit"), completion: Complete.units) var unit: String = ""
        @Flag(help: "형제 중 한 칸 위로") var up = false
        @Flag(help: "형제 중 한 칸 아래로") var down = false
        @Option(help: ArgumentHelp("이 단원 아래로", valueName: "unit"), completion: Complete.units) var parent: String?
        @Flag(help: "맨 위 단계로") var top = false

        func run() throws {
            guard [up, down, parent != nil, top].filter({ $0 }).count == 1 else {
                throw CLIError(exit: .usage, message: "--up, --down, --parent, --top 중 하나만 주세요")
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
