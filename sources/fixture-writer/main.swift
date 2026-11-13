import FolioFixtures
import Foundation

let args = CommandLine.arguments.dropFirst()
let kind = args.dropFirst().first ?? "standard"
let write: ((URL) throws -> Void)? =
    Fixture(rawValue: kind).map { f in { try f.write(to: $0) } } ?? Scenario(rawValue: kind).map { s in { try s.write(to: $0) } }
guard let path = args.first, let write else {
    let kinds = (["standard", "legacy"] + Scenario.allCases.map(\.rawValue)).joined(separator: "|")
    FileHandle.standardError.write(Data("usage: folio-fixture <folder> [\(kinds)]\n".utf8))
    exit(2)
}
let folder = URL(filePath: (path as NSString).expandingTildeInPath, directoryHint: .isDirectory)
// 이미 있는 폴더에 쓰면 그 안의 내용(실제 GIST 폴더일 수도 있다)에 픽스처가 섞인다.
if FileManager.default.fileExists(atPath: folder.path) {
    FileHandle.standardError.write(Data("folio-fixture: \(folder.path) already exists\n".utf8))
    exit(1)
}
try write(folder)
print(folder.path)
