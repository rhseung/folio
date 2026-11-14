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
