import Foundation

// A downloaded file waits in a folder of its own under the temporary directory until `lms accept` imports it into the
// course, so two files of one name from different classrooms never meet.
public enum LMSDownloads {
    public static func folder() throws -> URL {
        let folder = URL.temporaryDirectory.appending(path: "Folio-LMS/\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    // The LMS gives the uploader's file name; `Lectures` wants its own (`LMSFile.lectureName`).
    public static func rename(_ file: URL, to name: String) throws -> URL {
        let named = file.deletingLastPathComponent().appending(path: name)
        if named != file { try FileManager.default.moveItem(at: file, to: named) }
        return named
    }
}
