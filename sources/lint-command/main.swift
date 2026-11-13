import FolioLint
import Foundation

// Run from the repository root (mise runs every task there): paths in the report and the baseline are from it.
let root = FileManager.default.currentDirectoryPath
let baselinePath = root + "/.folio-lint-baseline.txt"
let update = CommandLine.arguments.dropFirst().contains("--update")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let code: Codebase
do { code = try Codebase(root: root) } catch { fail("folio-lint: \(error)") }

let rules = Rules.all
let found = rules.map { (rule: $0, hits: $0.hits(in: code)) }
let strict = found.filter(\.rule.strict).flatMap(\.hits)
let baselined = found.filter { !$0.rule.strict }.flatMap(\.hits)

var new = strict
var gone: [String] = []
if update {
    do { try Baseline.render(baselined).write(toFile: baselinePath, atomically: true, encoding: .utf8) } catch {
        fail("folio-lint: \(error)")
    }
    print("wrote \(baselined.count) entries to .folio-lint-baseline.txt")
} else {
    let known = (try? String(contentsOfFile: baselinePath, encoding: .utf8)).map(Baseline.entries) ?? []
    let report = Baseline.compare(baselined, with: known)
    new += report.new
    gone = report.gone
}

new.sort { ($0.path, $0.line) < ($1.path, $1.line) }
var lines: [String] = []
for rule in rules {
    let hits = new.filter { $0.check == rule.name }
    guard !hits.isEmpty else { continue }
    lines.append("\(rule.name): \(rule.advice)")
    lines += hits.map { "  \($0.path):\($0.line): \($0.key)" }
}
if !gone.isEmpty {
    lines.append(
        "Fixed or moved since .folio-lint-baseline.txt was written; run `mise run check-code -- --update` "
            + "to drop them (and check it adds nothing):")
    lines += gone.map { "  " + $0.replacingOccurrences(of: "\t", with: "  ") }
}
if !lines.isEmpty { fail(lines.joined(separator: "\n")) }
