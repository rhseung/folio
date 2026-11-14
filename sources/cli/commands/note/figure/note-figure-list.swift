import ArgumentParser
import FolioDomain
import FolioStorage
import Foundation

extension NoteCommand.Figure {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .noteFigureListAbstract))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpCourse), valueName: "course"), completion: .custom(Complete.courses))
        var course: String = ""

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let c = try r.course(course)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: c.store.fileURL(NoteFigure.folder).path)) ?? []
            let files = names.filter { $0.lowercased().hasSuffix(".svg") }.sorted()
            try listFiles(c, files.map { ($0, NoteFigure.path($0)) }, json: g.json)
        }
    }
}
