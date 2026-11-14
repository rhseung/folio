import FolioActions
import FolioDomain
import Foundation

@discardableResult
func perform<A: Action>(
    _ action: A, _ options: GlobalOptions, ctx given: ActionContext? = nil, done: @autoclosure () -> String, confirm: String? = nil,
    read: JSONValue? = nil
) throws -> ActionContext {
    if let confirm, !options.dryRun { try ask(confirm, options) }
    let ctx = try given ?? CLI.context(options)
    do {
        try action.run(ctx)
    } catch let e as ActionError {
        switch e {
        case .notFound(let m): throw CLIError(exit: .notFound, message: m)
        case .rule(let m): throw CLIError(exit: .rule, message: m)
        case .conflict(let m): throw CLIError(exit: .conflict, message: m)
        case .input(let m): throw CLIError(exit: .usage, message: m)
        }
    }
    if options.json {
        try printJSON(
            WriteResult(
                action: A.command, dryRun: options.dryRun, made: ctx.made, changes: ctx.changes.coalesced(), notes: ctx.notes, read: read))
    } else {
        renderChanges(ctx.changes.coalesced(), done: done(), dryRun: options.dryRun, root: ctx.gist.url)
        for n in ctx.notes { say("  · \(n)".styled(.dim)) }
    }
    return ctx
}

func renderChanges(_ changes: [Change], done: String, dryRun: Bool, root: URL) {
    say(dryRun ? String(localized: .performPreview).styled(.bold) + " · \(done)" : "✓".styled(.green) + " \(done)")
    if changes.isEmpty {
        say(String(localized: .performNoChange).styled(.dim))
        return
    }
    for c in changes {
        let mark =
            switch c.kind {
            case .added: "+".styled(.green)
            case .changed: "~".styled(.yellow)
            case .removed: "-".styled(.red)
            case .moved: "→".styled(.yellow)
            }
        let path = c.path.link(root.appending(path: c.path))
        let item = c.item.map { " " + $0.styled(.dim) } ?? ""
        let to = c.to.map { " → \($0)" } ?? ""
        say("  \(mark) \(path)\(item)\(to)")
        for f in c.fields ?? [] {
            say("      \(f.name): " + shown(f.before).styled(.dim) + " → " + shown(f.after))
        }
    }
}

func shown(_ v: JSONValue?) -> String {
    let text: String
    switch v {
    case nil, .null?: return String(localized: .performNone)
    case .string(let s)?: text = s
    case .bool(let b)?: text = b ? "true" : "false"
    case .number(let n)?: text = n == n.rounded() && abs(n) < 1e15 ? String(Int64(n)) : String(n)
    case let v?: text = (try? String(decoding: JSONEncoder().encode(v), as: UTF8.self)) ?? ""
    }
    return text.split(whereSeparator: \.isNewline).joined(separator: " ").truncated(to: 60)
}

// 에이전트가 기다리지 않고 멈추도록(종료 코드 5), 터미널이 아니면 `--yes`만 진행한다.
func ask(_ question: String, _ options: GlobalOptions) throws {
    guard !options.yes else { return }
    guard Style.isTerminal, isatty(STDIN_FILENO) == 1, !options.json else {
        throw CLIError(
            exit: .needsConfirmation, message: String(localized: .performNeedsConfirmation(question)),
            hints: [String(localized: .performYesHint), String(localized: .performDryRunHint)])
    }
    FileHandle.standardOutput.write(Data(String(localized: .performAsk(question)).utf8))
    guard let answer = readLine(), ["y", "yes", "ㅛ"].contains(answer.lowercased()) else {
        throw CLIError(exit: .needsConfirmation, message: String(localized: .performCancelled))
    }
}
