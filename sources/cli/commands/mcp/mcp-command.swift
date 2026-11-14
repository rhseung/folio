import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

struct MCPCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp", abstract: String(localized: .mcpAbstract), discussion: String(localized: .mcpDiscussion))

    @Option(help: ArgumentHelp(String(localized: .globalOptionsHelpGist), valueName: "path")) var gist: String?
    @Flag(help: ArgumentHelp(String(localized: .mcpHelpPropose))) var propose = false

    func run() throws {
        let server = MCPServer(gist: gist, propose: propose)
        // stdout이 프로토콜을 실으므로 답은 `print`의 버퍼를 거치지 않고 바로 쓴다.
        while let line = readLine() {
            guard let reply = server.handle(line) else { continue }
            FileHandle.standardOutput.write(reply + Data("\n".utf8))
        }
    }
}
