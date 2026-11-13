import FolioStorage
import Foundation

final class Pictures: @unchecked Sendable {
    struct Picture {
        var label: String
        var file: String
        var data: Data
        var mimeType = "image/jpeg"
    }

    private(set) var items: [Picture] = []

    @TaskLocal static var current: Pictures?

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

    // `resolvingSymlinksInPath`는 있는 경로에서만 `/private`(`/private/tmp`, `/private/var`)를 떼므로, GIST 폴더 안의 새
    // `--out` 폴더가 안에 있다고 비교되지 않는다. 그래서 있는 가장 가까운 폴더를 풀고 나머지를 다시 붙인다.
    private static func resolved(_ url: URL) -> URL {
        var base = url.standardizedFileURL, rest: [String] = []
        while !FileManager.default.fileExists(atPath: base.path), base.pathComponents.count > 1 {
            rest.insert(base.lastPathComponent, at: 0)
            base.deleteLastPathComponent()
        }
        return rest.reduce(base.resolvingSymlinksInPath()) { $0.appending(path: $1) }
    }
}
