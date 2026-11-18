import Foundation

public struct LMSKey: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    // `unsubmitted`, `due`, `attachments`는 받은 과제가 LMS와 다른 것(`LMSDifference`)이고, id는 LMS 과제 번호다.
    // `submitted`는 LMS에서 낸 과제를 Folio에서 제출함으로 바꿨다는 표시다(`lms submitted`). 사용자가 그 과제를 다시 할 일로
    // 돌리면 다음 동기화가 또 바꾸지 않게 남긴다.
    public enum Kind: String, Sendable, CaseIterable {
        case assignment, file, notice, submitted, unsubmitted, due, attachments
    }

    public var kind: Kind
    public var id: Int
    // 무시한 뒤 LMS가 다시 바뀌면 다시 제안하도록 무시한 값을 키에 남긴다. 마감 변경은 LMS 마감(분 단위 Unix 시각),
    // 새 첨부는 LMS가 보인 첨부 수다.
    public var stamp: Int?

    public init(kind: Kind, id: Int, stamp: Int? = nil) {
        self.kind = kind
        self.id = id
        self.stamp = stamp
    }

    public init?(_ text: String) {
        let parts = text.split(separator: ":", maxSplits: 2)
        guard parts.count >= 2, let kind = Kind(rawValue: String(parts[0])), let id = Int(parts[1]) else { return nil }
        var stamp: Int?
        if parts.count == 3 {
            guard let value = Int(parts[2]) else { return nil }
            stamp = value
        }
        self.init(kind: kind, id: id, stamp: stamp)
    }

    public var description: String { "\(kind.rawValue):\(id)" + (stamp.map { ":\($0)" } ?? "") }

    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let key = LMSKey(text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not an LMS key: \(text)"))
        }
        self = key
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }

    public static func < (a: LMSKey, b: LMSKey) -> Bool {
        (a.kind.rawValue, a.id, a.stamp ?? -1) < (b.kind.rawValue, b.id, b.stamp ?? -1)
    }
}
