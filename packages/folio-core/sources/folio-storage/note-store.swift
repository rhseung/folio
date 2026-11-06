import FolioDomain
import FolioMarkdown
import Foundation

/// The file name is the title; the course file's note entry at the same path holds the rest.
public struct NoteFile: Equatable, Sendable {
    public var url: URL
    public var meta: NoteMeta
    public var title: String { url.deletingPathExtension().lastPathComponent }
    public var format: NoteFormat { NoteFormat(path: url.path) ?? .markdown }

    public init(url: URL, meta: NoteMeta) {
        self.url = url
        self.meta = meta
    }
}

extension Array where Element == NoteFile {
    /// The note a link names by its title (Obsidian style): written as it is, or else ignoring case, as Obsidian
    /// also matches.
    public func titled(_ title: String) -> NoteFile? {
        first { $0.title == title } ?? first { $0.title.caseInsensitiveCompare(title) == .orderedSame }
    }

    /// The note a link by title (`[[제목]]`, `[[제목.md]]`) opens. Opening the link, drawing what it embeds and drawing
    /// it broken all ask this one rule, so a link never opens a note the preview says isn't there.
    public func linked(_ target: String) -> NoteFile? {
        titled(target.hasSuffix(".md") ? String(target.dropLast(3)) : target)
    }
}

extension NoteMeta {
    /// Folio's keys in a note's frontmatter, from before the properties moved to course.json. Only the one-time
    /// `note migrate` reads them.
    static let frontmatterKeys = ["id", "kind", "sessionId", "unitIds", "examId", "tags", "math"]

    init(frontmatter fm: Frontmatter) {
        self.init(
            id: fm["id"].flatMap(UUID.init(uuidString:)),
            kind: fm["kind"].flatMap(NoteKind.init(rawValue:)) ?? .free,
            sessionId: fm["sessionId"].flatMap(UUID.init(uuidString:)),
            unitIds: fm.list("unitIds").compactMap(UUID.init(uuidString:)),
            examId: fm["examId"].flatMap(UUID.init(uuidString:)),
            tags: fm.list("tags"),
            math: fm["math"].flatMap(MathSyntax.init(rawValue:)) ?? .latex
        )
    }
}

extension CourseStore {
    var notesURL: URL { url.appending(path: CourseFolder.notes.rawValue) }

    static let nonNoteFolders: Set<String> = [StandardLayout.noteAssetsFolder, StandardLayout.legacyNoteExportsFolder]

    /// The path a note entry stores. Note URLs are always built from the course folder, so the fallback is never
    /// taken in practice; it only spares callers an optional.
    public func notePath(of file: URL) -> String {
        coursePath(of: file) ?? "\(CourseFolder.notes.rawValue)/\(file.lastPathComponent)"
    }

    public func notes() throws -> [NoteFile] {
        notes(in: try load().model)
    }

    /// Every note file under Notes/, with the properties `file` has for it. A file without an entry (made outside
    /// Folio) has no id until it is adopted.
    public func notes(in file: CourseFile) -> [NoteFile] {
        let entries = Dictionary(file.notes.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        return noteURLs().map { NoteFile(url: $0, meta: entries[notePath(of: $0)].map(file.meta(of:)) ?? NoteMeta(id: nil)) }.sorted { $0.title < $1.title }
    }

    func noteURLs() -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: notesURL, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        var result: [URL] = []
        for case let url as URL in enumerator {
            if Self.nonNoteFolders.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
            } else if NoteFormat(path: url.path) != nil {
                result.append(url)
            }
        }
        return result
    }

    public func note(id: UUID) throws -> NoteFile? {
        try notes().first { $0.meta.id == id }
    }

    public func note(id: UUID, in file: CourseFile) -> NoteFile? {
        notes(in: file).first { $0.meta.id == id }
    }

    public func note(at path: String) throws -> NoteFile? {
        note(at: path, in: try load().model)
    }

    public func note(at path: String, in file: CourseFile) -> NoteFile? {
        let url = url.appending(path: path)
        guard NoteFormat(path: path) != nil, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return NoteFile(url: url, meta: file.notes.first { $0.path == notePath(of: url) }.map(file.meta(of:)) ?? NoteMeta(id: nil))
    }

    public func read(_ note: NoteFile) throws -> String {
        String(decoding: try CoordinatedFile.read(note.url), as: UTF8.self)
    }

    /// Writes `text` as it is. The note's properties live in course.json, so nothing is added to the file.
    public func write(_ note: NoteFile, text: String) throws {
        try CoordinatedFile.write(Data(text.utf8), to: note.url)
    }

    /// Where a new note titled `title` goes: `Notes/<title>.<ext>`, or ` 2`, ` 3`, ... when the name is taken.
    /// A name is taken in any format, since the title is the file name: `증명.md` beside `증명.tex` would be two notes
    /// that links and the list can't tell apart. `taken` holds names chosen for notes not written yet.
    public func newNoteURL(title: String, format: NoteFormat, avoiding taken: Set<String> = []) -> URL {
        let taken = Set(taken.map { $0.lowercased() })
        let isFree = { (name: String) in
            !taken.contains(name.lowercased()) && NoteFormat.allCases.allSatisfy {
                !FileManager.default.fileExists(atPath: self.notesURL.appending(path: "\(name).\($0.fileExtension)").path)
            }
        }
        let base = Self.fileName(for: title)
        var name = base
        var n = 2
        while !isFree(name) {
            name = "\(base) \(n)"
            n += 1
        }
        return notesURL.appending(path: "\(name).\(format.fileExtension)")
    }

    /// Where `note` goes renamed or moved to `path` in Notes/ (`정리/증명`; the note's own extension may be given), or nil
    /// for a folder notes can't be in or another format. A name another note of the course has gets ` 2`, ` 3`, ...,
    /// in any folder: a link names a note by its title alone (`[[증명]]`), so two of one title would share their links.
    public func movedNoteURL(_ note: NoteFile, to path: String, in file: CourseFile) -> URL? {
        var parts = path.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        guard var name = parts.popLast(),
              parts.allSatisfy({ !$0.isEmpty && !$0.hasPrefix(".") && !Self.nonNoteFolders.contains($0) }) else { return nil }
        if let format = NoteFormat(path: name) {
            guard format == note.format else { return nil }
            name = (name as NSString).deletingPathExtension
        }
        let key = { (title: String) in title.precomposedStringWithCanonicalMapping.lowercased() }
        let own = note.url.standardizedFileURL
        let taken = Set(notes(in: file).filter { $0.url.standardizedFileURL != own }.map { key($0.title) })
        let base = Self.fileName(for: name)
        var title = base
        var n = 2
        while taken.contains(key(title)) {
            title = "\(base) \(n)"
            n += 1
        }
        return parts.reduce(notesURL) { $0.appending(path: $1) }.appending(path: "\(title).\(note.format.fileExtension)")
    }

    /// Folders in Notes/ a note can be moved to, Notes-relative and sorted; Notes/ itself is "".
    public func noteFolders() -> [String] {
        guard let enumerator = FileManager.default.enumerator(at: notesURL, includingPropertiesForKeys: [.isDirectoryKey],
                                                              options: .skipsHiddenFiles) else { return [""] }
        var folders = [""]
        let root = notesURL.standardizedFileURL.pathComponents.count
        for case let url as URL in enumerator where (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            if Self.nonNoteFolders.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
            } else {
                folders.append(url.standardizedFileURL.pathComponents.dropFirst(root).joined(separator: "/"))
            }
        }
        return folders.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Where a note's PDF goes, by title, wherever in Notes/ the note sits: Study, with everything else self-made.
    /// Notes/ keeps only notes, and a PDF there would be listed as neither a note nor a material.
    public func exportPath(of note: NoteFile) -> String {
        "\(CourseFolder.study.rawValue)/\(note.title).pdf"
    }

    /// Creates the file only; the caller adds its entry to course.json.
    public func createNote(at url: URL, text: String) throws {
        try CoordinatedFile.write(Data(text.utf8), to: url)
    }

    /// To the Trash, not deleted: a note is the user's own writing. Its images stay in `assets/`, which other notes may share.
    public func trashNote(_ note: NoteFile) throws {
        try CoordinatedFile.trash(note.url)
    }

    public var noteAssetsURL: URL { notesURL.appending(path: StandardLayout.noteAssetsFolder) }

    public func noteAssets() -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: noteAssetsURL, includingPropertiesForKeys: keys, options: .skipsHiddenFiles)) ?? []
        func date(_ url: URL) -> Date { (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast }
        return files.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }.sorted { date($0) > date($1) }
    }

    /// How `note` links an asset path returned by `addNoteAsset` (`assets/x.png`); notes can sit in subfolders of Notes/.
    public func link(to assetPath: String, from note: NoteFile) -> String {
        let depth = note.url.deletingLastPathComponent().standardizedFileURL.pathComponents.count
            - notesURL.standardizedFileURL.pathComponents.count
        return String(repeating: "../", count: max(depth, 0)) + assetPath
    }

    @discardableResult
    public func addNoteAsset(_ file: URL) throws -> String {
        try addNoteAsset(named: file.lastPathComponent, data: try Data(contentsOf: file))
    }

    /// Saves `data` in `Notes/assets/` and returns the note-relative path. Never overwrites: the same bytes reuse the
    /// file already there, different bytes under a taken name get ` 2`, ` 3`, ...
    @discardableResult
    public func addNoteAsset(named name: String, data: Data) throws -> String {
        try FileManager.default.createDirectory(at: noteAssetsURL, withIntermediateDirectories: true)
        let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        var candidate = name
        var n = 2
        while true {
            let target = noteAssetsURL.appending(path: candidate)
            guard FileManager.default.fileExists(atPath: target.path) else {
                try CoordinatedFile.write(data, to: target)
                return "assets/\(candidate)"
            }
            if (try? CoordinatedFile.read(target)) == data { return "assets/\(candidate)" }
            candidate = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            n += 1
        }
    }

    /// Characters that break paths or Obsidian links become `-`.
    static func fileName(for title: String) -> String {
        let cleaned = title.map { "/\\:#^[]|".contains($0) ? "-" : $0 }
        let name = String(cleaned).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Untitled" : name
    }
}
