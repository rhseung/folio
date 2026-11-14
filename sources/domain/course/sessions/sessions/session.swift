import Foundation

public struct Session: Entity {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var updatedBy: DeviceID

    public var week: Int
    public var date: Date
    public var unitIds: [UUID]
    public var roughNoteId: UUID?
    public var reviewNoteId: UUID?
    public var inkIds: [UUID]
    public var materials: [SessionMaterial]
    public var end: Date?
    public var link: String?
    private var noReview: Bool?
    private var reviewNoteDraft: Bool?
    // 휴강인 회차만 `cancelled` 키를, 보강인 회차만 `makeup` 키를 가진다. `kind` 키 하나가 아니라 플래그 둘을 두어야
    // 보강이 생기기 전의 모든 파일이 그대로 읽힌다.
    private var cancelled: Bool?
    private var makeup: Bool?
    private var wrappedUp: Bool?

    public enum Kind: String, Codable, Sendable, CaseIterable {
        case lecture, cancelled, makeup
    }

    public var kind: Kind {
        get { cancelled == true ? .cancelled : makeup == true ? .makeup : .lecture }
        set {
            cancelled = newValue == .cancelled ? true : nil
            makeup = newValue == .makeup ? true : nil
        }
    }

    public var isCancelled: Bool {
        get { kind == .cancelled }
        set { if newValue { kind = .cancelled } else if kind == .cancelled { kind = .lecture } }
    }

    // 출석은 기록이 없는 것으로 저장하므로, 이 값이 없으면 직접 출석한 수업을 끝없이 묻게 된다. 정리에서 비워 둔
    // 칸도 일부러 비운 것으로 본다.
    public var isWrappedUp: Bool {
        get { wrappedUp ?? false }
        set { wrappedUp = newValue ? true : nil }
    }

    public var skipsReview: Bool {
        get { noReview ?? false }
        set { noReview = newValue ? true : nil }
    }

    public var reviewNoteUnfinished: Bool {
        get { reviewNoteId != nil && (reviewNoteDraft ?? false) }
        set { reviewNoteDraft = newValue ? true : nil }
    }

    public init(id: UUID = UUID(), device: DeviceID, at now: Date, week: Int, date: Date) {
        self.id = id
        self.createdAt = now
        self.updatedAt = now
        self.updatedBy = device
        self.week = week
        self.date = date
        self.unitIds = []
        self.inkIds = []
        self.materials = []
    }

    // 같은 시각의 두 수업(날짜만 가져온 회차)은 만든 순서를 지켜서 이름이 뒤바뀌지 않는다.
    public static func inOrder(_ a: Session, _ b: Session) -> Bool {
        (a.date, a.createdAt, a.id.uuidString) < (b.date, b.createdAt, b.id.uuidString)
    }

    public func needsReviewNote(at now: Date) -> Bool {
        !isCancelled && !skipsReview && date <= now && (reviewNoteId == nil || reviewNoteUnfinished)
    }
}

extension Session {
    public func slot(in schedule: [ClassTime], calendar: Calendar) -> ClassTime? {
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let weekday = calendar.isoWeekday(of: date)
        return schedule.first { $0.weekday == weekday && $0.startMinute == minute }
    }

    public func end(schedule: [ClassTime], calendar: Calendar) -> Date? {
        if let end = self.end { return end }
        guard let slot = slot(in: schedule, calendar: calendar) else { return nil }
        return date.addingTimeInterval(TimeInterval((slot.endMinute - slot.startMinute) * 60))
    }

    public func expectedEnd(schedule: [ClassTime], classMinutes: Int, calendar: Calendar) -> Date {
        end(schedule: schedule, calendar: calendar) ?? date.addingTimeInterval(TimeInterval((schedule.usualMinutes ?? classMinutes) * 60))
    }

    public func link(schedule: [ClassTime], calendar: Calendar) -> URL? {
        (self.link ?? slot(in: schedule, calendar: calendar)?.link).flatMap(OnlineLink.url)
    }

    // 시간표 칸이 이미 주는 끝 시각은 저장하지 않는다. 그래야 나중에 수업 시각을 바꾸면 회차의 끝 시각도 따라간다.
    public mutating func setEnd(_ end: Date?, schedule: [ClassTime], calendar: Calendar) {
        self.end = nil
        if let end, end != self.end(schedule: schedule, calendar: calendar) { self.end = end }
    }
}

extension Session {
    public func note(of kind: NoteKind) -> UUID? {
        switch kind {
        case .rough: roughNoteId
        case .review: reviewNoteId
        default: nil
        }
    }
}
