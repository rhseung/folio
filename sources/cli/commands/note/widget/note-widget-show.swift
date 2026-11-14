import ArgumentParser
import FolioDomain
import FolioStorage
import Foundation

extension NoteCommand.Widget {
    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .noteWidgetShowAbstract))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .noteWidgetHelpWidget), valueName: "widget")) var widget: String

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let (c, ref) = try r.split(widget)
            let id = try r.widget(ref, in: c)
            let text = try MaterialText.read(c.store, NoteWidget.path(id))
            if g.json {
                return try printJSON(NoteFileBody(name: id.uuidString, path: NoteWidget.path(id), text: text, hash: contentHash(text)))
            }
            say(text)
        }
    }
}
