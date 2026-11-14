import ArgumentParser
import FolioDomain
import FolioStorage
import Foundation

struct OpenCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "open", abstract: String(localized: .openAbstract), discussion: String(localized: .openDiscussion))
    @OptionGroup var g: GlobalOptions
    @OptionGroup var target: LinkTarget

    func run() throws {
        let resolved = try target.resolve(Resolver(try CLI.context(g)))
        // `swift test`에서 앱 창이 열리면 사용자의 포커스를 가져가므로, 테스트와 dry run은 출력만 한다.
        if !g.dryRun, CLI.overrides == nil {
            let p = Process()
            p.executableURL = URL(filePath: "/usr/bin/open")
            // 블록의 `^`는 URL에 쓸 수 없으므로 URL 꼴로 넘기고, 앱은 이스케이프된 값을 되읽는다(`AppLink(url:)`).
            p.arguments = [AppLink(string: resolved.link)?.url.absoluteString ?? resolved.link]
            try p.run()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else {
                throw CLIError(exit: .unexpected, message: String(localized: .openFailed(resolved.link)))
            }
        }
        if g.json { return try printJSON(resolved) }
        say(resolved.link)
    }
}
