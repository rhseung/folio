import Foundation

public enum Fixture: String, CaseIterable, Sendable {
    case standard
    case legacy

    var files: [(path: String, content: String?)] {
        switch self {
        case .standard: Self.standardFiles
        case .legacy: Self.legacyFiles
        }
    }

    // 내용이 없는 파일에는 자기 경로를 적은 줄을 써서, 모든 자리표시자(올바른 PDF가 아닌 `.pdf` 포함)의 hash가 서로
    // 다르게 한다. `/`로 끝나는 경로는 빈 폴더다.
    public func write(to folder: URL) throws {
        let fm = FileManager.default
        for (path, content) in files {
            let url = folder.appending(path: path)
            if path.hasSuffix("/") {
                try fm.createDirectory(at: url, withIntermediateDirectories: true)
                continue
            }
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data((content ?? "fixture placeholder: \(rawValue)/\(path)\n").utf8).write(to: url)
        }
    }

    public func copyToTemp() throws -> URL {
        let dest = FileManager.default.temporaryDirectory.appending(path: "folio-\(UUID().uuidString)/GIST")
        try write(to: dest)
        return dest
    }
}
