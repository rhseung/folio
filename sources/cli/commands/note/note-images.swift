import ArgumentParser
import FolioDomain
import FolioStorage
import Foundation
import PDFKit

extension NoteCommand {
    struct Images: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .noteImagesAbstract),
            discussion: String(localized: .noteImagesDiscussion(ReadingLimit.imageEdge, ReadingLimit.images)))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .noteImagesHelpNote), valueName: "note"), completion: Complete.notes) var note:
            String = ""
        @Option(help: ArgumentHelp(String(localized: .noteImagesHelpFile), valueName: "file")) var file: [String] = []
        @Option(help: ArgumentHelp(String(localized: .noteImagesHelpFrom(ReadingLimit.images)), valueName: "n")) var from: Int?
        @Option(help: ArgumentHelp(String(localized: .picturesHelpOut), valueName: "folder"), completion: .directory) var out: String?

        struct Item: Encodable {
            var index: Int
            var written: String
            var path: String?
            var image: String?
        }

        struct Shown: Encodable {
            var note: String?
            var pictures: [Item]
            var next: Int?
        }

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let c: CourseRef
            let found: (note: NoteFile, path: String)?
            if note.contains("/") {
                let (course, n, path) = try r.notePath(note)
                c = course
                found = (n, path)
            } else {
                c = try r.course(note)
                found = nil
            }

            let store = c.store
            let listed: [NoteImageFile]
            if !file.isEmpty {
                listed = try file.map { try Self.locate($0, in: store, near: found?.note) }
            } else if let found {
                listed = store.noteImageFiles(of: found.note, body: try store.read(found.note))
            } else {
                let assets = store.noteAssets().compactMap(store.coursePath(of:)).filter { MaterialFormat(path: $0) == .image }.sorted()
                return try show(Shown(note: nil, pictures: assets.enumerated().map { Item(index: $0 + 1, written: $1, path: $1) }), c)
            }

            let start = max(from ?? 1, 1)
            let window = Array(listed.enumerated().dropFirst(start - 1).prefix(ReadingLimit.images))
            let pictures = window.compactMap { i, f -> Pictures.Picture? in
                guard let path = f.path, let jpeg = store.pictureJPEG(path) else { return nil }
                let name = (path as NSString).lastPathComponent
                return Pictures.Picture(label: path, file: "\(i + 1) \((name as NSString).deletingPathExtension).jpg", data: jpeg)
            }
            let placed = try Pictures.hand(pictures, out: out, gist: r.ctx.gist.url)
            let placedAt = Dictionary(zip(pictures.map(\.label), placed), uniquingKeysWith: { a, _ in a })
            let last = start - 1 + window.count
            try show(
                Shown(
                    note: found?.path,
                    pictures: window.map { i, f in
                        Item(index: i + 1, written: f.written, path: f.path, image: f.path.flatMap { placedAt[$0] ?? nil })
                    },
                    next: last < listed.count ? last + 1 : nil), c)
        }

        func show(_ shown: Shown, _ c: CourseRef) throws {
            if g.json { return try printJSON(shown) }
            if shown.pictures.isEmpty { return say(String(localized: .noteImagesNone).styled(.dim)) }
            for p in shown.pictures {
                say(
                    "\(p.index). ".styled(.dim) + (p.path ?? p.written)
                        + (p.path == nil ? "  " + String(localized: .noteImagesMissing).styled(.yellow) : ""))
                if let image = p.image { say("   → \(image)".styled(.dim)) }
            }
            if let next = shown.next, let note = shown.note {
                say(
                    String(localized: .readingNext("folio note images \(MaterialCommand.Read.quoted("\(c.code)/\(note)")) --from \(next)"))
                        .styled(.dim))
            }
        }

        static func locate(_ written: String, in store: CourseStore, near note: NoteFile?) throws -> NoteImageFile {
            guard MaterialFormat(path: written) == .image else {
                throw CLIError(exit: .usage, message: String(localized: .noteImagesNotImage(written)))
            }
            let notes = CourseFolder.notes.rawValue
            let candidates =
                (note.flatMap { store.coursePath(of: $0.url.deletingLastPathComponent().appending(path: written)) }.map { [$0] } ?? [])
                + ["\(notes)/\(StandardLayout.noteAssetsFolder)/\(written)", "\(notes)/\(written)", written]
            guard
                let path = candidates.first(where: { store.contains($0) && FileManager.default.fileExists(atPath: store.fileURL($0).path) })
            else {
                throw CLIError(exit: .notFound, message: String(localized: .noteImagesNotFound(written)))
            }
            return NoteImageFile(written: written, path: path)
        }
    }
}
