import Foundation

public struct LMSSettings: Codable, Sendable, Equatable {
    public var known: [Int]
    public var handled: [LMSKey]

    public init(known: [Int] = [], handled: [LMSKey] = []) {
        self.known = known
        self.handled = handled
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        known = try c.decodeIfPresent([Int].self, forKey: .known) ?? []
        handled = try c.decodeIfPresent([LMSKey].self, forKey: .handled) ?? []
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
