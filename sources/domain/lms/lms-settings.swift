import Foundation

public struct LMSSettings: Codable, Sendable, Equatable {
    public var known: [Int]
    public var handled: [LMSKey]
    public var syncMinutes: Int

    public init(known: [Int] = [], handled: [LMSKey] = [], syncMinutes: Int = SettingItem.lmsSyncMinutes.int) {
        self.known = known
        self.handled = handled
        self.syncMinutes = syncMinutes
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        known = try c.decodeIfPresent([Int].self, forKey: .known) ?? []
        handled = try c.decodeIfPresent([LMSKey].self, forKey: .handled) ?? []
        syncMinutes = try c.value(.syncMinutes, or: SettingItem.lmsSyncMinutes.int)
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
