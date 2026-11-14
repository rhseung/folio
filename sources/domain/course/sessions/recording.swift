import Foundation

public struct Recording: Entity {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var updatedBy: DeviceID

    public var sessionId: UUID?
    public var file: String
    public var startedAt: Date
    public var duration: TimeInterval
    public var bookmarks: [TimeInterval]
    public var audioTrashedAt: Date?
    public var pages: [PageVisit]

    public var hasAudio: Bool { audioTrashedAt == nil }

    public init(
        id: UUID = UUID(), device: DeviceID, at now: Date, sessionId: UUID?, file: String, duration: TimeInterval = 0,
        bookmarks: [TimeInterval] = [],
        pages: [PageVisit] = []
    ) {
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

    public var transcriptFile: String { Self.transcriptFile(of: file) }

    public static let transcriptSuffix = ".transcript.json"

    public static func transcriptFile(of audio: String) -> String { (audio as NSString).deletingPathExtension + transcriptSuffix }

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

public struct PageVisit: Codable, Sendable, Equatable {
    public var at: TimeInterval
    public var materialId: UUID
    public var page: Int?

    public init(at: TimeInterval, materialId: UUID, page: Int?) {
        self.at = at
        self.materialId = materialId
        self.page = page
    }
}

extension Recording {
    // 한 쪽을 듣고 있다고 볼 만큼 머문 시간이다. 쪽을 찾으며 넘기면 다른 쪽은 1초나 2초 안에 지나간다.
    public static let pageDwell: TimeInterval = 20

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

    public func visit(_ material: UUID, page: Int?, at time: TimeInterval) -> PageVisit? {
        let last = pages.last
        if page == nil, last?.materialId != material || last?.page == nil { return nil }
        if last?.materialId == material, last?.page == page { return nil }
        return PageVisit(at: time, materialId: material, page: page)
    }
}

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
    public var context: TranscriptionContext?

    public init(locale: String, lines: [Line] = [], context: TranscriptionContext? = nil) {
        self.locale = locale
        self.lines = lines
        self.context = context
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        locale = try c.decode(String.self, forKey: .locale)
        lines = try c.decode([Line].self, forKey: .lines)
        // 새 판이 이 판이 못 읽는 꼴로 쓴 맥락은 보조 정보일 뿐이므로 무시하고 줄만 읽는다.
        context = try? c.decodeIfPresent(TranscriptionContext.self, forKey: .context)
    }

    public func lineIndex(at time: TimeInterval) -> Int? {
        var low = 0, high = lines.count
        while low < high {
            let mid = (low + high) / 2
            if lines[mid].start <= time { low = mid + 1 } else { high = mid }
        }
        return low == 0 ? nil : low - 1
    }

    public var text: String { lines.map(\.text).joined(separator: "\n") }

    // 충돌로 끊긴 자막은 오디오보다 한참 먼저 끝난다. 마지막 문장을 아직 해독하는 동안 몇 초마다 저장하기 때문이다.
    // 침묵으로 이어진 강의도 이 검사에 걸려 다시 듣게 되지만, 시간만 더 든다.
    public func reaches(_ duration: TimeInterval) -> Bool {
        guard let last = lines.last else { return false }
        return last.end >= duration - Self.tailAllowance
    }

    static let tailAllowance: TimeInterval = 60

    // 아무것도 듣지 못한(조용한 방이거나 모든 줄이 군말인) 받아쓰기가 기존 자막을 지우면 안 된다. 옛 파일을 기록한
    // 곳이 없어서 되찾을 수 없기 때문이다.
    public func replaces(_ existing: LectureTranscript?) -> Bool {
        !lines.isEmpty || existing?.lines.isEmpty != false
    }
}
