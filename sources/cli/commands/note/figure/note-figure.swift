import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

extension NoteCommand {
    struct Figure: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .noteFigureAbstract),
            subcommands: subcommandTypes)
    }
}

func sayFiles(_ items: [NoteFileItem]) {
    var t = Table(header: [String(localized: .noteFileHeaderName), String(localized: .noteFileHeaderNotes)], shrink: [1])
    for i in items { t.rows.append([i.name, i.notes.joined(separator: ", ")]) }
    t.print()
    footer(items.count)
}
