import Foundation

/// They live in code and are written out on demand, so the public repository carries no folder of course files.
public enum Fixture: String, CaseIterable, Sendable {
    case standard
    /// The unorganized shape of the real folder. Only for cleanup-tool tests.
    case legacy

    var files: [(path: String, content: String?)] {
        switch self {
        case .standard: Self.standardFiles
        case .legacy: Self.legacyFiles
        }
    }

    /// A file without content gets a line naming its own path, so every placeholder (the `.pdf`s too, which are not
    /// valid PDFs) has a distinct hash.
    public func write(to folder: URL) throws {
        let fm = FileManager.default
        for (path, content) in files {
            let url = folder.appending(path: path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data((content ?? "fixture placeholder: \(rawValue)/\(path)\n").utf8).write(to: url)
        }
    }

    /// A fresh copy under the temp directory, so a test never sees another test's writes.
    public func copyToTemp() throws -> URL {
        let dest = FileManager.default.temporaryDirectory.appending(path: "folio-\(UUID().uuidString)/GIST")
        try write(to: dest)
        return dest
    }
}
