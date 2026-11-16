import FolioDomain
import Foundation

extension CourseStore {
    public var recordingsURL: URL { url.appending(path: CourseFolder.recordings.rawValue) }

    public func newRecordingFile(named base: String, reserved: [String] = []) throws -> String {
        try FileManager.default.createDirectory(at: recordingsURL, withIntermediateDirectories: true)
        let onDisk = (try? FileManager.default.contentsOfDirectory(atPath: recordingsURL.path)) ?? []
        return Recording.file(named: base, taken: Set(onDisk + reserved.map { ($0 as NSString).lastPathComponent }))
    }

    public func installRecording(from local: URL, as coursePath: String) throws -> String {
        var path = coursePath
        if FileManager.default.fileExists(atPath: fileURL(path).path) {
            path = try newRecordingFile(named: ((coursePath as NSString).lastPathComponent as NSString).deletingPathExtension)
        }
        try FileManager.default.createDirectory(at: recordingsURL, withIntermediateDirectories: true)
        try CoordinatedFile.move(local, to: fileURL(path))
        return path
    }

    public func trashAudio(of recording: Recording) throws {
        let url = fileURL(recording.file)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try CoordinatedFile.trash(url)
    }

    // 조정된 읽기는 iCloud가 비운 오디오를 내려받는데, 받아쓰기처럼 긴 읽기에서 조정을 몇 분씩 잡고 있으면 다른 기기의
    // 쓰기가 멈춘다. 그래서 GIST 폴더 밖에 복사해 읽는다.
    public func copyAudio(of recording: Recording, to target: URL) throws {
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try CoordinatedFile.copy(fileURL(recording.file), to: target)
    }

    public func audioSize(of recording: Recording) -> Int64 {
        guard recording.hasAudio else { return 0 }
        return Int64((try? fileURL(recording.file).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    public func deleteFiles(of recording: Recording) throws {
        try CoordinatedFile.remove(fileURL(recording.file))
        try CoordinatedFile.remove(fileURL(recording.transcriptFile))
    }

    public func saveTranscript(_ transcript: LectureTranscript, of recording: Recording) throws {
        try CoordinatedFile.write(try JSONFormat.encoder.encode(transcript), to: fileURL(recording.transcriptFile))
    }

    public func transcript(of recording: Recording) -> LectureTranscript? {
        (try? CoordinatedFile.read(fileURL(recording.transcriptFile))).flatMap {
            try? JSONFormat.decoder.decode(LectureTranscript.self, from: $0)
        }
    }
}
