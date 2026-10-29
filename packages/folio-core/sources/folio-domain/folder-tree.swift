/// Snapshot of a folder on disk. Storage reads it once; layout and tracking rules then run on it as pure functions.
public struct FolderTree: Hashable, Sendable {
    public enum Content: Hashable, Sendable {
        case file(size: Int64)
        case folder([FolderTree])
        /// A folder shown as a single item and not descended into.
        case opaque(OpaqueReason)
    }

    public enum OpaqueReason: Hashable, Sendable {
        case codeProject
        case tooManyFiles
    }

    public var name: String
    public var content: Content

    public init(name: String, content: Content) {
        self.name = name
        self.content = content
    }

    public var children: [FolderTree] {
        if case .folder(let children) = content { children } else { [] }
    }

    public var isFile: Bool {
        if case .file = content { true } else { false }
    }

    public subscript(child name: String) -> FolderTree? {
        children.first { $0.name == name }
    }

    public var fileCount: Int {
        switch content {
        case .file: 1
        case .folder(let children): children.reduce(0) { $0 + $1.fileCount }
        case .opaque: 0
        }
    }
}
