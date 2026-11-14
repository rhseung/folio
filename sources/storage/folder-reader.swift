import FolioDomain
import Foundation

extension FolderTree {
    // shortcut: 아직 내려받지 않은 iCloud placeholder도 보통 파일로 읽는다. 이름이 `.x.icloud`로 보이면 ubiquitous 내려받기 상태를 확인한다.
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
        let children =
            try urls
            .filter { !IndexRules.isIgnoredFile($0.lastPathComponent) }
            .map { try FolderTree(contentsOf: $0, depth: depth + 1) }
            .sorted { $0.name < $1.name }
        let tree = FolderTree(name: url.lastPathComponent, content: .folder(children))
        self =
            depth >= IndexRules.firstCollapsibleDepth && tree.fileCount > IndexRules.maxIndexedFiles
            ? FolderTree(name: url.lastPathComponent, content: .opaque(.tooManyFiles))
            : tree
    }
}
