import Foundation

public typealias DeviceID = UUID

/// Every stored entity carries these so iCloud conflict copies can be merged item by item (newer `updatedAt` wins).
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

/// A calendar date without time or time zone, stored as `yyyy-MM-dd`.
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
    /// Keeps the first value of a repeated key. Ids come from files people copy and edit, and a repeat must not crash
    /// the app the way `uniqueKeysWithValues` does.
    public init<S: Sequence>(keepingFirst pairs: S) where S.Element == (Key, Value) {
        self.init(pairs, uniquingKeysWith: { first, _ in first })
    }
}
