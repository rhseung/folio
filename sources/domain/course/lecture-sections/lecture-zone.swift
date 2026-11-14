import Foundation

public struct LectureZone: Equatable, Sendable {
    public var firstPage: Int
    public var lastPage: Int
    public var units: [UUID]

    public init(firstPage: Int, lastPage: Int, units: [UUID]) {
        self.firstPage = firstPage
        self.lastPage = lastPage
        self.units = units
    }

    public var pages: ClosedRange<Int> { firstPage...lastPage }
}
