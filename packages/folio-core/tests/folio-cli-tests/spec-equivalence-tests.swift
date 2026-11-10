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

    // It writes beside the backup folder, which the three copies share, so the second run finds the first's folder;
    // today-backup-tests checks it against the action instead.
    static let outsideGIST: Set<String> = ["backup restore"]

    static let examples: [(String, String)] = Actions.all.filter { $0.spec.generated && !outsideGIST.contains($0.command) }
        .flatMap { type in type.spec.examples.filter(HelpExampleTests.runnable).map { (type.command, $0.replacing(/\s{2,}\S.*$/, with: "")) } }

    // Preparing runs two dozen commands, and every example starts from the same prepared folder, so it is prepared
    // once and copied. The copy takes the backup folder along and points the settings at it: examples running side by
    // side must not write into one backup folder.
    static let prepared = Result {
        let gist = try Harness.fixtureCopy()
        try HelpExampleTests().prepare(gist)
        return gist.deletingLastPathComponent()
    }

    func preparedCopy() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "folio-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: try Self.prepared.get(), to: folder)
        let gist = folder.appending(path: "GIST")
        var settings = try GISTStore(url: gist).loadSettings().model
        settings.backup.folder = folder.appending(path: "backups").path
        try h.direct(SettingsSet(settings: settings), gist: gist)
        return gist
    }

    @Test(arguments: examples)
    func threeWaysAgree(_ command: String, _ example: String) throws {
        let base = try preparedCopy()
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
