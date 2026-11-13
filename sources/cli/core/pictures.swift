import FolioStorage
import Foundation

/// Pictures a read command hands over. Under `folio mcp` they go to Claude as image content, each after a line naming
/// it; at a terminal they are files in `--out`. Base64 in the JSON would reach Claude as tens of thousands of
/// characters of text instead of a picture.
final class Pictures: @unchecked Sendable {
    struct Picture {
        /// What Claude is told the picture is, on the line before it.
        var label: String
        /// Its file name under `--out`.
        var file: String
        var data: Data
        var mimeType = "image/jpeg"
    }

    private(set) var items: [Picture] = []

    @TaskLocal static var current: Pictures?

    /// Where each picture went, for the output to name: its file under `out`, its label when Claude gets it, nil when
    /// neither (a terminal without `--out`, told once on stderr).
    static func hand(_ pictures: [Picture], out: String?, gist: URL) throws -> [String?] {
        guard !pictures.isEmpty else { return [] }
        if let current {
            current.items += pictures
            return pictures.map(\.label)
        }
        guard let out else {
            warn(String(localized: .picturesNeedOut))
            return pictures.map { _ in nil }
        }
        let folder = URL(filePath: absolute(out), directoryHint: .isDirectory)
        // The GIST folder changes only through actions; pictures made for reading don't belong in it.
        let root = resolved(gist).path + "/"
        guard !(resolved(folder).path + "/").hasPrefix(root) else {
            throw CLIError(exit: .usage, message: String(localized: .picturesOutInGist(out)))
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try pictures.map { p in
            let file = folder.appending(path: p.file.replacing("/", with: "-"))
            try p.data.write(to: file, options: .atomic)
            return file.path
        }
    }

    /// `resolvingSymlinksInPath` drops `/private` (of `/private/tmp`, `/private/var`) only from a path that exists, so
    /// a new `--out` folder inside the GIST folder would not compare as inside it. Resolve the nearest folder that
    /// exists and put the rest back.
    private static func resolved(_ url: URL) -> URL {
        var base = url.standardizedFileURL, rest: [String] = []
        while !FileManager.default.fileExists(atPath: base.path), base.pathComponents.count > 1 {
            rest.insert(base.lastPathComponent, at: 0)
            base.deleteLastPathComponent()
        }
        return rest.reduce(base.resolvingSymlinksInPath()) { $0.appending(path: $1) }
    }
}
