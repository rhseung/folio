import Foundation

public struct RecordingRetitle: Equatable, Sendable {
    public var recording: UUID
    public var file: String
    public var name: String

    public init(recording: UUID, file: String, name: String) {
        self.recording = recording
        self.file = file
        self.name = name
    }
}
