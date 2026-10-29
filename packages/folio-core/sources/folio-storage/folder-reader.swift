import FolioDomain
import Foundation

extension FolderTree {
    /// Reads a folder, skipping ignored files and not descending into code projects or oversized folders (IndexRules).
    /// `depth` is the depth of `url` below the GIST root (0 for the root, 2 for a course folder).
    // shortcut: iCloud placeholders are read as regular files; check ubiquitous download status if names show up as `.x.icloud`.
    public init(contentsOf url: URL, depth: Int = 0) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        guard values.isDirectory == true else {
            self.init(name: url.lastPathComponent, content: .file(size: Int64(values.fileSize ?? 0)))
            return
        }
        let urls = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey])
        if depth > IndexRules.courseFolderDepth, IndexRules.isCodeProject(childNames: urls.map(\.lastPathComponent)) {
            self.init(name: url.lastPathComponent, content: .opaque(.codeProject))
            return
        }
        let children = try urls
            .filter { !IndexRules.isIgnoredFile($0.lastPathComponent) }
            .map { try FolderTree(contentsOf: $0, depth: depth + 1) }
            .sorted { $0.name < $1.name }
        let tree = FolderTree(name: url.lastPathComponent, content: .folder(children))
        self = depth >= IndexRules.firstCollapsibleDepth && tree.fileCount > IndexRules.maxIndexedFiles
            ? FolderTree(name: url.lastPathComponent, content: .opaque(.tooManyFiles))
            : tree
    }
}
