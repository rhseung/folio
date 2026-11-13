import FolioLint
import Foundation

// Run from the repository root (mise runs every task there): paths in the report and the baseline are from it.
let root = FileManager.default.currentDirectoryPath
let baselinePath = root + "/packages/folio-lint/baseline.txt"
let update = CommandLine.arguments.dropFirst().contains("--update")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let code: Codebase
do { code = try Codebase(root: root) } catch { fail("folio-lint: \(error)") }

let rules = Rules.all
let hits = rules.flatMap { $0.hits(in: code) }

if update {
    do { try Baseline.render(hits).write(toFile: baselinePath, atomically: true, encoding: .utf8) } catch {
        fail("folio-lint: \(error)")
    }
    print("wrote \(hits.count) entries to packages/folio-lint/baseline.txt")
    exit(0)
}

let known = (try? String(contentsOfFile: baselinePath, encoding: .utf8)).map(Baseline.entries) ?? []
let report = Baseline.compare(hits, with: known)
var lines: [String] = []
for rule in rules {
    let found = report.new.filter { $0.check == rule.name }
    guard !found.isEmpty else { continue }
    lines.append("\(rule.name): \(rule.advice)")
    lines += found.map { "  \($0.path):\($0.line): \($0.key)" }
}
if !report.gone.isEmpty {
    lines.append("Fixed or moved since packages/folio-lint/baseline.txt was written; run `mise run check-code -- --update` "
        + "to drop them (and check it adds nothing):")
    lines += report.gone.map { "  " + $0.replacingOccurrences(of: "\t", with: "  ") }
}
if !report.passed { fail(lines.joined(separator: "\n")) }
