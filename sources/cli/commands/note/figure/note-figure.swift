import ArgumentParser
import FolioDomain
import FolioStorage
import Foundation

extension NoteCommand {
    struct Figure: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .noteFigureAbstract),
            subcommands: [List.self, Show.self, Render.self] + GeneratedCommands.noteFigure)
    }
}

func readFigure(_ c: CourseRef, _ name: String) throws -> (String, String) {
    guard let file = NoteFigure.fileName(name) else { throw CLIError(exit: .usage, message: String(localized: .noteFigureBadName(name))) }
    return (file, try MaterialText.read(c.store, NoteFigure.path(file)))
}

func listFiles(_ c: CourseRef, _ files: [(name: String, path: String)], json: Bool) throws {
    let notes = (try? c.store.notes()) ?? []
    let texts = notes.compactMap { n in (try? c.store.read(n)).map { (c.store.coursePath(of: n.url) ?? n.url.lastPathComponent, $0) } }
    let items = files.map { f in
        let values = try? c.store.fileURL(f.path).resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return NoteFileItem(
            name: f.name, path: f.path, size: values?.fileSize ?? 0, modified: values?.contentModificationDate,
            notes: texts.filter { $0.1.contains(f.name) }.map(\.0))
    }
    if json { return try printJSON(items) }
    var t = Table(header: [String(localized: .noteFileHeaderName), String(localized: .noteFileHeaderNotes)], shrink: [1])
    for i in items { t.rows.append([i.name, i.notes.joined(separator: ", ")]) }
    t.print()
    footer(items.count)
}
