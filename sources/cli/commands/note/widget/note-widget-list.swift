import ArgumentParser
import FolioDomain
import FolioStorage
import Foundation

extension NoteCommand.Widget {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .noteWidgetListAbstract))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpCourse), valueName: "course"), completion: .custom(Complete.courses))
        var course: String = ""

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let c = try r.course(course)
            let folder = StandardLayout.metadataFolder + "/" + StandardLayout.widgetsFolder
            let names = (try? FileManager.default.contentsOfDirectory(atPath: c.store.fileURL(folder).path)) ?? []
            let ids = names.compactMap { n in n.hasSuffix(".html") ? UUID(uuidString: String(n.dropLast(5))) : nil }.map(\.uuidString)
                .sorted()
            try listFiles(c, ids.map { ($0, NoteWidget.path(UUID(uuidString: $0)!)) }, json: g.json)
        }
    }
}
