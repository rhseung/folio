import FolioFixtures
import Foundation

let args = CommandLine.arguments.dropFirst()
let kind = args.dropFirst().first ?? "standard"
// A scenario is the standard folder grown into a day with sessions, recordings and dues, for running the app on.
let write: ((URL) throws -> Void)? = Fixture(rawValue: kind).map { f in { try f.write(to: $0) } } ?? Scenario(rawValue: kind).map { s in { try s.write(to: $0) } }
guard let path = args.first, let write else {
    let kinds = (["standard", "legacy"] + Scenario.allCases.map(\.rawValue)).joined(separator: "|")
    FileHandle.standardError.write(Data("usage: folio-fixture <folder> [\(kinds)]\n".utf8))
    exit(2)
}
let folder = URL(filePath: (path as NSString).expandingTildeInPath, directoryHint: .isDirectory)
// Writing over an existing folder would mix the fixture into whatever is there, maybe a real GIST folder.
if FileManager.default.fileExists(atPath: folder.path) {
    FileHandle.standardError.write(Data("folio-fixture: \(folder.path) already exists\n".utf8))
    exit(1)
}
try write(folder)
print(folder.path)
