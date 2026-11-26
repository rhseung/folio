import Foundation

public enum LMSDownloads {
    public static func folder() throws -> URL {
        let folder = URL.temporaryDirectory.appending(path: "Folio-LMS/\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
