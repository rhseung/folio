import Foundation

/// One lecture recording (docs/SPEC.md "강의 녹음"): an audio file under `Recordings/`, with its transcript beside it.
public struct Recording: Entity {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var updatedBy: DeviceID

    public var sessionId: UUID?
    /// Course-relative path of the audio, e.g. `Recordings/3주차-1.m4a`.
    public var file: String
    public var startedAt: Date
    /// Seconds of audio; pauses are not recorded, so this can be shorter than the class.
    public var duration: TimeInterval
    /// Seconds into the audio marked while recording.
    public var bookmarks: [TimeInterval]

    public init(id: UUID = UUID(), device: DeviceID, at now: Date, sessionId: UUID?, file: String, duration: TimeInterval = 0, bookmarks: [TimeInterval] = []) {
        self.id = id
        self.createdAt = now
        self.updatedAt = now
        self.updatedBy = device
        self.sessionId = sessionId
        self.file = file
        self.startedAt = now
        self.duration = duration
        self.bookmarks = bookmarks
    }

    public var transcriptFile: String { (file as NSString).deletingPathExtension + ".transcript.json" }

    public static func file(named base: String, taken: Set<String>) -> String {
        var name = "\(base).m4a"
        var n = 2
        while taken.contains(name) {
            name = "\(base) \(n).m4a"
            n += 1
        }
        return "\(CourseFolder.recordings.rawValue)/\(name)"
    }
}

/// What was said, in timed lines. Kept in its own file because it is large and only the recording screen reads it.
public struct LectureTranscript: Codable, Sendable, Equatable {
    public struct Line: Codable, Sendable, Equatable {
        public var start: TimeInterval
        public var end: TimeInterval
        public var text: String

        public init(start: TimeInterval, end: TimeInterval, text: String) {
            self.start = start
            self.end = end
            self.text = text
        }
    }

    public var schemaVersion = 1
    public var locale: String
    public var lines: [Line]

    public init(locale: String, lines: [Line] = []) {
        self.locale = locale
        self.lines = lines
    }

    /// The line being spoken at `time`: the last one that has started. Lines are in time order.
    public func lineIndex(at time: TimeInterval) -> Int? {
        var low = 0, high = lines.count
        while low < high {
            let mid = (low + high) / 2
            if lines[mid].start <= time { low = mid + 1 } else { high = mid }
        }
        return low == 0 ? nil : low - 1
    }

    public var text: String { lines.map(\.text).joined(separator: "\n") }
}
