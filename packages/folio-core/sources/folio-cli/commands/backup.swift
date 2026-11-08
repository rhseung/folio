import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

struct BackupCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "backup", abstract: String(localized: .backupAbstract), subcommands: GeneratedCommands.backup + [List.self])

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .backupListAbstract), discussion: String(localized: .backupListDiscussion))
        @OptionGroup var g: GlobalOptions

        func run() throws {
            let ctx = try CLI.context(g)
            let folder = URL(filePath: (try ctx.settings().backup.folder as NSString).expandingTildeInPath, directoryHint: .isDirectory)
            let archives = BackupStore(gist: ctx.gist, folder: folder).archives()
            struct Row: Encodable { var day: String; var path: String }
            if g.json { return try printJSON(archives.map { Row(day: $0.day.description, path: $0.url.path(percentEncoded: false)) }) }
            var t = Table(header: [String(localized: .backupListHeaderDate), String(localized: .backupListHeaderFile)], shrink: [1])
            for a in archives { t.rows.append([a.day.description, a.url.path(percentEncoded: false).link(a.url)]) }
            t.print()
            footer(archives.count)
        }
    }

}
