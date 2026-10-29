@testable import FolioCLI
import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Testing

/// Every example of an action declared with `@Action` runs three ways on the same prepared folder: as the command,
/// as `run --input` with the input the command built, and as the decoded action itself. All three must leave the
/// same files, so the generated command, `run` and the action can't drift apart.
struct SpecEquivalenceTests {
    let h = Harness()

    static let examples: [(String, String)] = Actions.all.filter { $0.spec.generated }
        .flatMap { type in type.spec.examples.map { (type.command, $0.replacing(/\s{2,}\S.*$/, with: "")) } }

    @Test(arguments: examples)
    func threeWaysAgree(_ command: String, _ example: String) throws {
        let base = try Harness.fixtureCopy()
        try HelpExampleTests().prepare(base)
        let args = Array(HelpExampleTests.words(example).dropFirst()).filter { $0 != "--dry-run" } + ["--yes"]
        let copies = try (0..<3).map { _ in try copy(base) }

        let built = Recorded()
        let r = Built.$record.withValue({ name, json in built.add(name, json) }) { h.cli(args, gist: copies[0]) }
        #expect(r.code == 0, "\(example): \(r.err)")
        let input = try #require(built.items.first { $0.0 == command }?.1, "\(example) built no \(command)")
        let text = String(decoding: try JSONEncoder().encode(input), as: UTF8.self)

        let viaRun = h.cli(["run"] + command.split(separator: " ").map(String.init) + ["--input", text, "--yes"], gist: copies[1])
        #expect(viaRun.code == 0, "run \(command): \(viaRun.err)")
        let type = try #require(Actions.all.first { $0.command == command })
        try h.direct(try type.decode(JSONEncoder().encode(input)), gist: copies[2])

        let files = try copies.map { try Harness.files($0) }
        for (i, way) in ["run --input", "직접 실행"].enumerated() {
            #expect(files[0].keys.sorted() == files[i + 1].keys.sorted(), "\(example): files differ via \(way)")
            for (path, data) in files[0] where Harness.canonical(files[i + 1][path]) != Harness.canonical(data) {
                Issue.record("\(example): \(path) differs via \(way)")
            }
        }
    }

    func copy(_ base: URL) throws -> URL {
        let to = FileManager.default.temporaryDirectory.appending(path: "spec-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: base, to: to)
        return to
    }
}

private final class Recorded: @unchecked Sendable {
    var items: [(String, JSONValue)] = []
    func add(_ name: String, _ json: JSONValue) { items.append((name, json)) }
}
