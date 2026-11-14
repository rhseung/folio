import ArgumentParser
import FolioDomain
import FolioStorage
import Foundation

extension NoteCommand.Figure {
    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .noteFigureShowAbstract))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpCourse), valueName: "course"), completion: .custom(Complete.courses))
        var course: String
        @Argument(help: ArgumentHelp(String(localized: .noteFigureHelpName), valueName: "name")) var name: String

        func run() throws {
            let c = try Resolver(try CLI.context(g)).course(course)
            let (file, text) = try readFigure(c, name)
            if g.json {
                return try printJSON(NoteFileBody(name: file, path: NoteFigure.path(file), text: text, hash: contentHash(text)))
            }
            say(text)
        }
    }
}
