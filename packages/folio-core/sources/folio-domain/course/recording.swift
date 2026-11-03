import Foundation

/// One lecture recording: an audio file under `Recordings/`, with its transcript beside it.
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
    /// When the audio went to the Trash to save space, its transcript and bookmarks kept. Nil while the audio is there.
    public var audioTrashedAt: Date?
    /// Lecture pages on screen while recording, in time order.
    public var pages: [PageVisit]

    public var hasAudio: Bool { audioTrashedAt == nil }

    public init(id: UUID = UUID(), device: DeviceID, at now: Date, sessionId: UUID?, file: String, duration: TimeInterval = 0, bookmarks: [TimeInterval] = [],
                pages: [PageVisit] = []) {
        self.id = id
        self.createdAt = now
        self.updatedAt = now
        self.updatedBy = device
        self.sessionId = sessionId
        self.file = file
        self.startedAt = now
        self.duration = duration
        self.bookmarks = bookmarks
        self.pages = pages
    }

    // Recordings saved before pages were kept have none, which needs no migration.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        updatedBy = try c.decode(DeviceID.self, forKey: .updatedBy)
        sessionId = try c.decodeIfPresent(UUID.self, forKey: .sessionId)
        file = try c.decode(String.self, forKey: .file)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        duration = try c.decode(TimeInterval.self, forKey: .duration)
        bookmarks = try c.decodeIfPresent([TimeInterval].self, forKey: .bookmarks) ?? []
        audioTrashedAt = try c.decodeIfPresent(Date.self, forKey: .audioTrashedAt)
        pages = try c.decodeIfPresent([PageVisit].self, forKey: .pages) ?? []
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

/// A lecture page put on screen `at` seconds into the audio; it stays there until the next visit.
public struct PageVisit: Codable, Sendable, Equatable {
    public var at: TimeInterval
    public var materialId: UUID
    /// 1-based; nil when the file was closed.
    public var page: Int?

    public init(at: TimeInterval, materialId: UUID, page: Int?) {
        self.at = at
        self.materialId = materialId
        self.page = page
    }
}

extension Recording {
    /// Long enough on a page to be listening to it; paging through to find one passes others in a second or two.
    public static let pageDwell: TimeInterval = 20

    /// The pages of each file the class went through, in the order first opened: from the first to the last page
    /// that stayed on screen for `pageDwell`. The last visit stops at `duration`: the audio so far while recording.
    public func viewedPages() -> [SessionMaterial] {
        var ranges: [SessionMaterial] = []
        for (i, visit) in pages.enumerated() {
            guard let page = visit.page else { continue }
            let leftAt = i + 1 < pages.count ? pages[i + 1].at : duration
            guard leftAt - visit.at >= Self.pageDwell else { continue }
            if let j = ranges.firstIndex(where: { $0.materialId == visit.materialId }) {
                ranges[j].firstPage = min(ranges[j].firstPage ?? page, page)
                ranges[j].lastPage = max(ranges[j].lastPage ?? page, page)
            } else {
                ranges.append(SessionMaterial(materialId: visit.materialId, firstPage: page, lastPage: page))
            }
        }
        return ranges
    }

    /// The next visit when `page` of `material` comes on screen (nil: the file closed), or nil when nothing changed.
    public func visit(_ material: UUID, page: Int?, at time: TimeInterval) -> PageVisit? {
        let last = pages.last
        if page == nil, last?.materialId != material || last?.page == nil { return nil }
        if last?.materialId == material, last?.page == page { return nil }
        return PageVisit(at: time, materialId: material, page: page)
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
    /// What the recognizer was told. Nil in transcripts made before it was kept.
    public var context: TranscriptionContext?

    public init(locale: String, lines: [Line] = [], context: TranscriptionContext? = nil) {
        self.locale = locale
        self.lines = lines
        self.context = context
    }

    // `context` is a key added without a version bump: missing means "not kept", as with a course.json section.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        locale = try c.decode(String.self, forKey: .locale)
        lines = try c.decode([Line].self, forKey: .lines)
        // A context a newer version wrote in a shape this one can't read is only a help: the lines still are.
        context = try? c.decodeIfPresent(TranscriptionContext.self, forKey: .context)
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

    /// Captions cut off by a crash end well before the audio does: they are saved every few seconds while the last
    /// sentences are still being decoded. A lecture that runs on in silence fails this too and is heard again, which
    /// costs only time.
    public func reaches(_ duration: TimeInterval) -> Bool {
        guard let last = lines.last else { return false }
        return last.end >= duration - Self.tailAllowance
    }

    static let tailAllowance: TimeInterval = 60

    /// A transcript made from the audio that heard nothing (a quiet room, or every line a filler) must not wipe the
    /// captions: nothing records the old file, so it could not be got back.
    public func replaces(_ existing: LectureTranscript?) -> Bool {
        !lines.isEmpty || existing?.lines.isEmpty != false
    }
}
