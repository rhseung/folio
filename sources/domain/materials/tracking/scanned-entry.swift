import Foundation

public struct ScannedEntry: Hashable, Sendable {
    public var path: String
    public var isFolder: Bool
    public var size: Int64?

    public init(path: String, isFolder: Bool = false, size: Int64? = nil) {
        self.path = path
        self.isFolder = isFolder
        self.size = size
    }

    public static func materials(in course: FolderTree) -> [ScannedEntry] {
        func walk(_ node: FolderTree, _ path: String) -> [ScannedEntry] {
            switch node.content {
            case .file(let size): [ScannedEntry(path: path, size: size)]
            case .opaque: [ScannedEntry(path: path, isFolder: true)]
            case .folder(let children): children.flatMap { walk($0, "\(path)/\($0.name)") }
            }
        }
        return course.children
            .filter { CourseFolder(rawValue: $0.name)?.holdsMaterials ?? true }
            .flatMap { walk($0, $0.name) }
    }
}
