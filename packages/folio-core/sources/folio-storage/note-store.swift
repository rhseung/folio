import FolioDomain
import FolioMarkdown
import Foundation

/// A markdown note in `Notes/`. The file name is the title; the frontmatter `id` is the identity.
public struct NoteFile: Equatable, Sendable {
    public var url: URL
    public var meta: NoteMeta
    public var title: String { url.deletingPathExtension().lastPathComponent }
}

extension NoteMeta {
    init(_ fm: Frontmatter) {
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

    /// Writes these fields into `fm`, leaving every other key as it was.
    public func apply(to fm: inout Frontmatter) {
        fm["id"] = id?.uuidString
        fm["kind"] = kind.rawValue
        fm["sessionId"] = sessionId?.uuidString
        fm.setList("unitIds", unitIds.map(\.uuidString))
        fm["examId"] = examId?.uuidString
        fm.setList("tags", tags)
        fm["math"] = math == .latex ? nil : math.rawValue
    }
}

extension CourseStore {
    var notesURL: URL { url.appending(path: CourseFolder.notes.rawValue) }

    /// Subfolders of Notes/ that hold attachments or exports, not notes.
    static let nonNoteFolders: Set<String> = [StandardLayout.noteAssetsFolder, StandardLayout.noteExportsFolder]

    public func notes() throws -> [NoteFile] {
        guard let enumerator = FileManager.default.enumerator(at: notesURL, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        var result: [NoteFile] = []
        for case let url as URL in enumerator {
            if Self.nonNoteFolders.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
            } else if url.pathExtension == "md" {
                // One unreadable note (still downloading, permissions) shouldn't empty the whole list.
                guard let data = try? CoordinatedFile.read(url) else { continue }
                let text = String(decoding: data, as: UTF8.self)
                result.append(NoteFile(url: url, meta: NoteMeta(Frontmatter.split(text).frontmatter)))
            }
        }
        return result.sorted { $0.title < $1.title }
    }

    public func note(id: UUID) throws -> NoteFile? {
        try notes().first { $0.meta.id == id }
    }

    /// The note at a course-relative path, reading only that file.
    public func note(at path: String) throws -> NoteFile? {
        let url = url.appending(path: path)
        guard url.pathExtension == "md", FileManager.default.fileExists(atPath: url.path) else { return nil }
        let text = String(decoding: try CoordinatedFile.read(url), as: UTF8.self)
        return NoteFile(url: url, meta: NoteMeta(Frontmatter.split(text).frontmatter))
    }

    public func read(_ note: NoteFile) throws -> String {
        String(decoding: try CoordinatedFile.read(note.url), as: UTF8.self)
    }

    /// Saves the full text; the frontmatter is rewritten from `note.meta`, keeping keys Folio doesn't know.
    public func save(_ note: NoteFile, text: String) throws {
        var (fm, body) = Frontmatter.split(text)
        note.meta.apply(to: &fm)
        try CoordinatedFile.write(Data(fm.render(body: body).utf8), to: note.url)
    }

    /// Writes `text` as it is, frontmatter included.
    public func write(_ note: NoteFile, text: String) throws {
        try CoordinatedFile.write(Data(text.utf8), to: note.url)
    }

    /// The note's id, written into its frontmatter first if it has none (notes made outside Folio).
    public func ensureID(_ note: NoteFile) throws -> UUID {
        if let id = note.meta.id { return id }
        let id = UUID()
        var file = note
        file.meta.id = id
        try save(file, text: try read(note))
        return id
    }

    /// Creates `Notes/<title>.md` with `body`, or the template for its kind. A taken name gets ` 2`, ` 3`, ...
    public func createNote(title: String, meta: NoteMeta, body: String? = nil) throws -> NoteFile {
        let base = Self.fileName(for: title)
        var name = base
        var n = 2
        while FileManager.default.fileExists(atPath: notesURL.appending(path: "\(name).md").path) {
            name = "\(base) \(n)"
            n += 1
        }
        let note = NoteFile(url: notesURL.appending(path: "\(name).md"), meta: meta)
        try save(note, text: body ?? NoteTemplate.body(for: meta.kind, title: title))
        return note
    }

    /// To the Trash, not deleted: a note is the user's own writing. Its images stay in `assets/`, which other notes may share.
    public func trashNote(_ note: NoteFile) throws {
        try CoordinatedFile.trash(note.url)
    }

    public var noteAssetsURL: URL { notesURL.appending(path: StandardLayout.noteAssetsFolder) }

    /// Files in `Notes/assets/`, newest first.
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

    /// Copies `file` into `Notes/assets/`. Returns the note-relative path.
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
