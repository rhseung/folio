import FolioDomain
import Foundation

public struct PendingRecording: Codable, Sendable, Equatable {
    public var courseId: UUID
    public var recording: Recording

    public init(courseId: UUID, recording: Recording) {
        self.courseId = courseId
        self.recording = recording
    }
}

public struct PendingRecordings: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public func audioURL(of id: UUID) -> URL { url.appending(path: "\(id.uuidString).caf") }
    public func compressedURL(of id: UUID) -> URL { url.appending(path: "\(id.uuidString).m4a") }
    private func infoURL(of id: UUID) -> URL { url.appending(path: "\(id.uuidString).json") }

    public func save(_ pending: PendingRecording) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try JSONFormat.encoder.encode(pending).write(to: infoURL(of: pending.recording.id), options: .atomic)
    }

    public func all() -> [PendingRecording] {
        let files = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { file in
            guard let data = try? Data(contentsOf: file),
                let pending = try? JSONFormat.decoder.decode(PendingRecording.self, from: data),
                FileManager.default.fileExists(atPath: audioURL(of: pending.recording.id).path)
            else { return nil }
            return pending
        }
    }

    public func remove(_ id: UUID) {
        for file in [audioURL(of: id), compressedURL(of: id), infoURL(of: id)] { try? FileManager.default.removeItem(at: file) }
    }
}
