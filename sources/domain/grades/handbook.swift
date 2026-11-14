import Foundation

public struct Handbook: Codable, Sendable, Equatable {
    public var year: Int
    public var source: String
    public var areas: [String: String]

    public init(year: Int, source: String, areas: [String: String]) {
        self.year = year
        self.source = source
        self.areas = areas
    }
}
