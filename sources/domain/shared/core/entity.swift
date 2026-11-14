import Foundation

public typealias DeviceID = UUID

public protocol Entity: Identifiable, Codable, Sendable, Equatable where ID == UUID {
    var createdAt: Date { get set }
    var updatedAt: Date { get set }
    var updatedBy: DeviceID { get set }
}

extension Entity {
    public mutating func touch(by device: DeviceID, at date: Date) {
        updatedAt = date
        updatedBy = device
    }
}

public struct LocalDate: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public var year: Int
    public var month: Int
    public var day: Int

    public init?(year: Int, month: Int, day: Int) {
        guard DateComponents(calendar: Calendar(identifier: .gregorian), year: year, month: month, day: day).isValidDate
        else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    public init?(_ string: String) {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let date = LocalDate(year: parts[0], month: parts[1], day: parts[2]),
            date.description == string
        else { return nil }
        self = date
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (a: Self, b: Self) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    public init(from decoder: any Decoder) throws {
        let string = try decoder.singleValueContainer().decode(String.self)
        guard let date = LocalDate(string) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not yyyy-MM-dd: \(string)"))
        }
        self = date
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

extension Dictionary {
    // ID는 사람이 복사하고 고치는 파일에서 오므로 키가 겹칠 수 있다. `uniqueKeysWithValues`는 겹친 키에서 앱을
    // 비정상 종료시키므로, 여기서는 첫 값을 쓴다.
    public init<S: Sequence>(keepingFirst pairs: S) where S.Element == (Key, Value) {
        self.init(pairs, uniquingKeysWith: { first, _ in first })
    }
}
