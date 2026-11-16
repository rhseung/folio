import Foundation

public struct LMSSettings: Codable, Sendable, Equatable {
    public var known: [Int]
    public var handled: [LMSKey]
    public var syncMinutes: Int
    // JSON 객체의 키는 문자열이어야 하므로 강의실 번호를 문자열로 둔다. `[Int: _]`는 배열로 쓰인다.
    public var rooms: [String: LMSRoom]

    public init(
        known: [Int] = [], handled: [LMSKey] = [], syncMinutes: Int = SettingItem.lmsSyncMinutes.int, rooms: [String: LMSRoom] = [:]
    ) {
        self.known = known
        self.handled = handled
        self.syncMinutes = syncMinutes
        self.rooms = rooms
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        known = try c.decodeIfPresent([Int].self, forKey: .known) ?? []
        handled = try c.decodeIfPresent([LMSKey].self, forKey: .handled) ?? []
        syncMinutes = try c.value(.syncMinutes, or: SettingItem.lmsSyncMinutes.int)
        rooms = try c.decodeIfPresent([String: LMSRoom].self, forKey: .rooms) ?? [:]
    }

    public func room(_ classroom: Int) -> LMSRoom? { rooms[String(classroom)] }

    // 기억한 과목이다. 기억이 없거나 "과목 없음"이면 nil이다.
    public func course(of classroom: Int) -> UUID? { room(classroom)?.course }

    // 과목 열 끝에 두는, 이 과목을 기억한 강의실이다.
    public func classrooms(of course: UUID, in snapshot: LMSSnapshot) -> [LMSClassroom] {
        snapshot.classrooms.filter { self.course(of: $0.id) == course }
    }

    // nil이면 기억을 지운다.
    public mutating func remember(_ room: LMSRoom?, for classroom: Int) {
        rooms[String(classroom)] = room
    }

    // 학교 전체가 쓰는 서버라 확인 주기보다 자주 읽지 않는다. 실패한 시도도 한 번으로 센다.
    public func syncDue(lastAttempt: Date?, now: Date) -> Bool {
        lastAttempt.map { now.timeIntervalSince($0) >= TimeInterval(syncMinutes * 60) } ?? true
    }

    // 두 기기가 같은 일을 하면 같은 파일을 쓰도록, 두 목록은 정렬하고 중복 없이 둔다.
    public mutating func know(_ classrooms: [Int]) {
        known = Set(known).union(classrooms).sorted()
    }

    public mutating func mark(_ keys: [LMSKey], handled on: Bool) {
        var set = Set(handled)
        if on { set.formUnion(keys) } else { set.subtract(keys) }
        handled = set.sorted()
    }

    public func unseen(in snapshot: LMSSnapshot) -> [LMSClassroom] {
        let known = Set(known)
        return snapshot.classrooms.filter { !known.contains($0.id) }
    }
}
