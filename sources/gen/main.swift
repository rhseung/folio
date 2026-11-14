import FolioActions
import Foundation

// 생성한 파일은 모두 커밋한다. `--check`는 디스크의 파일이 지금 선언에서 만든 것과 같은지만 본다.
let check = CommandLine.arguments.dropFirst().contains("--check")
let root = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../..").standardizedFileURL
let actionsFolder = root.appending(path: "sources/actions")
let commandsFolder = root.appending(path: "sources/cli/commands")
let generatedActions = root.appending(path: "sources/actions/generated")
let generatedCommands = root.appending(path: "sources/cli/generated")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

do {
    let declared = try ActionList.scan(actionsFolder)
    var files: [URL: String] = [generatedActions.appending(path: "actions-all.swift"): ActionList.source(declared)]

    // 이 실행 파일에 링크된 Actions.all은 지난번에 만든 목록이다. 액션을 더하거나 뺐으면 목록만 먼저 쓰고, 다시 빌드한
    // 다음 실행에서 명령을 쓴다(`mise run gen-cli`가 두 번 돌린다).
    let linked = Dictionary(Actions.all.map { (String(describing: $0), $0) }, uniquingKeysWith: { a, _ in a })
    let current = Set(linked.keys) == Set(declared.map(\.name))
    if current {
        files[generatedCommands.appending(path: "generated-commands.swift")] = CommandSource.commandsEnum
        for action in declared {
            guard let type = linked[action.name], type.spec.generated else { continue }
            files[generatedCommands.appending(path: action.path)] = CommandSource.file(type)
        }
        let tree = try CommandTree.scan(commandsFolder)
        files[generatedCommands.appending(path: "command-tree.swift")] = try CommandTree.source(tree, generated: Actions.all)
    }

    var stale: [String] = []
    for folder in [generatedActions] + (current ? [generatedCommands] : []) {
        for path in swiftFiles(in: folder) where files[folder.appending(path: path)] == nil {
            stale.append(folder.appending(path: path).path)
            if !check { try FileManager.default.removeItem(at: folder.appending(path: path)) }
        }
    }
    for (url, text) in files.sorted(by: { $0.key.path < $1.key.path }) {
        let old = try? String(contentsOf: url, encoding: .utf8)
        guard old != text else { continue }
        stale.append(url.path)
        if !check {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
    if check {
        if !current { fail("Actions.all이(가) sources/actions의 @Action 선언과 다릅니다. mise run gen-cli로 다시 만드세요.") }
        if !stale.isEmpty {
            fail("생성한 파일이 선언과 다릅니다. mise run gen-cli로 다시 만드세요:\n" + stale.map { "  " + $0 }.joined(separator: "\n"))
        }
    } else if !current {
        print("액션 목록을 새로 썼습니다. 다시 빌드한 뒤 명령을 씁니다.")
    }
} catch {
    fail("folio-gen: \(error)")
}

func swiftFiles(in folder: URL) -> [String] {
    guard let walker = FileManager.default.enumerator(atPath: folder.path) else { return [] }
    return walker.compactMap { $0 as? String }.filter { $0.hasSuffix(".swift") }
}
