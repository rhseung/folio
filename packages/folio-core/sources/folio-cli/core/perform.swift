import FolioActions
import FolioDomain
import Foundation

struct WriteResult: Encodable {
    var action: String
    var dryRun: Bool
    var made: UUID?
    var changes: [Change]
    var notes: [String]
}

@discardableResult
func perform<A: Action>(_ action: A, _ options: GlobalOptions, ctx given: ActionContext? = nil, done: @autoclosure () -> String, confirm: String? = nil) throws -> ActionContext {
    if let confirm, !options.dryRun { try ask(confirm, options) }
    let ctx = try given ?? CLI.context(options)
    do {
        try action.run(ctx)
    } catch let e as ActionError {
        switch e {
        case .notFound(let m): throw CLIError(exit: .notFound, message: m)
        case .rule(let m): throw CLIError(exit: .rule, message: m)
        case .conflict(let m): throw CLIError(exit: .conflict, message: m)
        }
    }
    if options.json {
        try printJSON(WriteResult(action: A.command, dryRun: options.dryRun, made: ctx.made, changes: ctx.changes.coalesced(), notes: ctx.notes))
    } else {
        renderChanges(ctx.changes.coalesced(), done: done(), dryRun: options.dryRun, root: ctx.gist.url)
        for n in ctx.notes { say("  · \(n)".styled(.dim)) }
    }
    return ctx
}

func renderChanges(_ changes: [Change], done: String, dryRun: Bool, root: URL) {
    say(dryRun ? "미리보기".styled(.bold) + " · \(done)" : "✓".styled(.green) + " \(done)")
    if changes.isEmpty {
        say("  바뀐 것 없음".styled(.dim))
        return
    }
    for c in changes {
        let mark = switch c.kind {
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

/// A field value on one line: strings bare, absent as 없음, anything nested as compact JSON cut to fit.
func shown(_ v: JSONValue?) -> String {
    let text: String
    switch v {
    case nil, .null?: return "없음"
    case .string(let s)?: text = s
    case .bool(let b)?: text = b ? "true" : "false"
    case .number(let n)?: text = n == n.rounded() && abs(n) < 1e15 ? String(Int64(n)) : String(n)
    case let v?: text = (try? String(decoding: JSONEncoder().encode(v), as: UTF8.self)) ?? ""
    }
    return text.split(whereSeparator: \.isNewline).joined(separator: " ").truncated(to: 60)
}

/// `[y/N]` at a terminal; anywhere else only `--yes` goes ahead, so an agent stops instead of waiting (exit 5).
func ask(_ question: String, _ options: GlobalOptions) throws {
    guard !options.yes else { return }
    guard Style.isTerminal, isatty(STDIN_FILENO) == 1, !options.json else {
        throw CLIError(exit: .needsConfirmation, message: "확인이 필요합니다: \(question)", hints: ["사용자가 승인했으면 --yes를 붙여 다시 실행", "--dry-run으로 미리 보기"])
    }
    FileHandle.standardOutput.write(Data("\(question) 계속할까요? [y/N] ".utf8))
    guard let answer = readLine(), ["y", "yes", "ㅛ"].contains(answer.lowercased()) else {
        throw CLIError(exit: .needsConfirmation, message: "취소했습니다")
    }
}
