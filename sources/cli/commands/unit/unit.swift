import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

func treePrefix(_ depths: [Int], at i: Int) -> String {
    let d = depths[i]
    guard d > 0 else { return "" }
    func continues(_ level: Int) -> Bool {
        for j in (i + 1)..<depths.count {
            if depths[j] < level { return false }
            if depths[j] == level { return true }
        }
        return false
    }
    return (1..<d).map { continues($0) ? "│  " : "   " }.joined() + (continues(d) ? "├─ " : "└─ ")
}

func performAll<A: Action>(_ actions: [A], _ options: GlobalOptions, ctx: ActionContext, done: String) throws {
    for a in actions.dropLast() {
        do {
            try a.run(ctx)
        } catch let e as ActionError {
            switch e {
            case .notFound(let m): throw CLIError(exit: .notFound, message: m)
            case .rule(let m): throw CLIError(exit: .rule, message: m)
            case .conflict(let m): throw CLIError(exit: .conflict, message: m)
            case .input(let m): throw CLIError(exit: .usage, message: m)
            }
        }
    }
    try perform(actions[actions.count - 1], options, ctx: ctx, done: done)
}
