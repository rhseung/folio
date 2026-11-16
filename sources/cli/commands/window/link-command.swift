import ArgumentParser
import FolioDomain
import FolioStorage
import Foundation

struct LinkCommand: ParsableCommand, HandRead {

    static let reason = "종류마다 대상을 다르게 읽고 앵커 옵션을 주소로 짓는다"
    static let configuration = CommandConfiguration(
        commandName: "link", abstract: String(localized: .linkAbstract), discussion: String(localized: .linkDiscussion))
    @OptionGroup var g: GlobalOptions
    @OptionGroup var target: LinkTarget

    func run() throws {
        let resolved = try target.resolve(Resolver(try CLI.context(g)))
        if g.json { return try printJSON(resolved) }
        say(resolved.link)
    }
}
