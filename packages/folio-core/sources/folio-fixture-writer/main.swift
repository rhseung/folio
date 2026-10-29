import FolioFixtures
import Foundation

// `folio-fixture <folder> [standard|legacy]`: writes a fake GIST folder for running the app or the CLI on.

let args = CommandLine.arguments.dropFirst()
guard let path = args.first, let fixture = Fixture(rawValue: args.dropFirst().first ?? "standard") else {
    FileHandle.standardError.write(Data("usage: folio-fixture <folder> [standard|legacy]\n".utf8))
    exit(2)
}
let folder = URL(filePath: (path as NSString).expandingTildeInPath, directoryHint: .isDirectory)
// Writing over an existing folder would mix the fixture into whatever is there, maybe a real GIST folder.
if FileManager.default.fileExists(atPath: folder.path) {
    FileHandle.standardError.write(Data("folio-fixture: \(folder.path) already exists\n".utf8))
    exit(1)
}
try fixture.write(to: folder)
print(folder.path)
