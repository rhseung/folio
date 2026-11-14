import Foundation

public enum LMSDownloads {
    public static func folder() throws -> URL {
        let folder = URL.temporaryDirectory.appending(path: "Folio-LMS/\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    public static func rename(_ file: URL, to name: String) throws -> URL {
        let named = file.deletingLastPathComponent().appending(path: name)
        if named != file { try FileManager.default.moveItem(at: file, to: named) }
        return named
    }
}
