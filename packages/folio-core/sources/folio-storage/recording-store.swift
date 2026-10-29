import FolioDomain
import Foundation

extension CourseStore {
    public var recordingsURL: URL { url.appending(path: CourseFolder.recordings.rawValue) }

    /// A course-relative path for a new recording named after `base` (a session name), never one already on disk or
    /// in `reserved` (recordings listed in course.json whose audio isn't in place yet).
    public func newRecordingFile(named base: String, reserved: [String] = []) throws -> String {
        try FileManager.default.createDirectory(at: recordingsURL, withIntermediateDirectories: true)
        let onDisk = (try? FileManager.default.contentsOfDirectory(atPath: recordingsURL.path)) ?? []
        return Recording.file(named: base, taken: Set(onDisk + reserved.map { ($0 as NSString).lastPathComponent }))
    }

    /// Moves finished audio from outside the GIST folder to `coursePath`, or the next free name if another file took
    /// it meanwhile (another device). Returns the path it landed at; never replaces a file.
    public func installRecording(from local: URL, as coursePath: String) throws -> String {
        var path = coursePath
        if FileManager.default.fileExists(atPath: fileURL(path).path) {
            path = try newRecordingFile(named: ((coursePath as NSString).lastPathComponent as NSString).deletingPathExtension)
        }
        try FileManager.default.createDirectory(at: recordingsURL, withIntermediateDirectories: true)
        try CoordinatedFile.move(local, to: fileURL(path))
        return path
    }

    /// The audio and its transcript. Only after the user confirmed the deletion.
    public func deleteFiles(of recording: Recording) throws {
        try CoordinatedFile.remove(fileURL(recording.file))
        try CoordinatedFile.remove(fileURL(recording.transcriptFile))
    }

    public func saveTranscript(_ transcript: LectureTranscript, of recording: Recording) throws {
        try CoordinatedFile.write(try JSONFormat.encoder.encode(transcript), to: fileURL(recording.transcriptFile))
    }

    public func transcript(of recording: Recording) -> LectureTranscript? {
        (try? CoordinatedFile.read(fileURL(recording.transcriptFile))).flatMap { try? JSONFormat.decoder.decode(LectureTranscript.self, from: $0) }
    }
}
