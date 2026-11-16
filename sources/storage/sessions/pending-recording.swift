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
