import FolioDomain
import FolioMarkdown
import Foundation

extension Array where Element == NoteFile {
    public func titled(_ title: String) -> NoteFile? {
        first { $0.title == title } ?? first { $0.title.caseInsensitiveCompare(title) == .orderedSame }
    }

    public func linked(_ target: String) -> NoteFile? {
        titled(target.hasSuffix(".md") ? String(target.dropLast(3)) : target)
    }
}

extension NoteMeta {
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

    public func notePath(of file: URL) -> String {
        coursePath(of: file) ?? "\(CourseFolder.notes.rawValue)/\(file.lastPathComponent)"
    }

    public func notes() throws -> [NoteFile] {
        notes(in: try load().model)
    }

    public func notes(in file: CourseFile) -> [NoteFile] {
        let entries = Dictionary(file.notes.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        return noteURLs().map { NoteFile(url: $0, meta: entries[notePath(of: $0)].map(file.meta(of:)) ?? NoteMeta(id: nil)) }.sorted {
            $0.title < $1.title
        }
    }

    func noteURLs() -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: notesURL, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }
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

    public func write(_ note: NoteFile, text: String) throws {
        try CoordinatedFile.write(Data(text.utf8), to: note.url)
    }

    // 제목이 파일 이름이므로 이름은 어느 형식에서든 겹친다. `증명.tex` 옆의 `증명.md`는 링크와 목록이 구분하지 못하는
    // 두 노트가 된다.
    public func newNoteURL(title: String, format: NoteFormat, avoiding taken: Set<String> = []) -> URL {
        let taken = Set(taken.map { $0.lowercased() })
        let isFree = { (name: String) in
            !taken.contains(name.lowercased())
                && NoteFormat.allCases.allSatisfy {
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

    // 링크는 제목만으로 노트를 가리키므로(`[[증명]]`) 같은 제목의 노트 둘은 링크를 나눠 갖게 된다. 그래서 과목의 다른
    // 노트가 가진 이름이면 어느 폴더든 ` 2`, ` 3`을 붙인다.
    public func movedNoteURL(_ note: NoteFile, to path: String, in file: CourseFile) -> URL? {
        var parts = path.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        guard var name = parts.popLast(), parts.allSatisfy({ StandardLayout.noteFolderProblem($0) == nil }) else { return nil }
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

    public func noteFolders() -> [String] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: notesURL, includingPropertiesForKeys: [.isDirectoryKey],
                options: .skipsHiddenFiles)
        else { return [""] }
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

    public func exportPath(of note: NoteFile) -> String {
        "\(CourseFolder.study.rawValue)/\(note.title).pdf"
    }

    public func builtPDF(of note: NoteFile, in file: CourseFile) -> String? {
        guard note.format == .tex, let id = note.meta.id, let made = file.notes.first(where: { $0.id == id })?.builtHash else { return nil }
        let path = exportPath(of: note)
        return (try? hash(path)) == made ? path : nil
    }

    public func builtPDFMove(of note: NoteFile, to url: URL, in file: CourseFile) -> BuiltPDFMove? {
        guard let from = builtPDF(of: note, in: file) else { return nil }
        let to = exportPath(of: NoteFile(url: url, meta: note.meta))
        guard to != from else { return nil }
        return BuiltPDFMove(from: from, to: to, blocked: FileManager.default.fileExists(atPath: fileURL(to).path))
    }

    public func createNote(at url: URL, text: String) throws {
        try CoordinatedFile.write(Data(text.utf8), to: url)
    }

    public func trashNote(_ note: NoteFile) throws {
        try CoordinatedFile.trash(note.url)
    }

    public var noteAssetsURL: URL { notesURL.appending(path: StandardLayout.noteAssetsFolder) }

    public func noteAssets() -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        let files =
            (try? FileManager.default.contentsOfDirectory(at: noteAssetsURL, includingPropertiesForKeys: keys, options: .skipsHiddenFiles))
            ?? []
        func date(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        return files.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }.sorted { date($0) > date($1) }
    }

    public func link(to assetPath: String, from note: NoteFile) -> String {
        let depth =
            note.url.deletingLastPathComponent().standardizedFileURL.pathComponents.count
            - notesURL.standardizedFileURL.pathComponents.count
        return String(repeating: "../", count: max(depth, 0)) + assetPath
    }

    @discardableResult
    public func addNoteAsset(_ file: URL) throws -> String {
        try addNoteAsset(named: file.lastPathComponent, data: try Data(contentsOf: file))
    }

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

    static func fileName(for title: String) -> String {
        let cleaned = title.map { "/\\:#^[]|".contains($0) ? "-" : $0 }
        let name = String(cleaned).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Untitled" : name
    }
}
