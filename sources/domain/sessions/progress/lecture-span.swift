import Foundation

public struct LectureSpan: Equatable, Sendable {
    public var firstPage: Int
    public var lastPage: Int
    public var sessions: [UUID]

    public init(firstPage: Int, lastPage: Int, sessions: [UUID]) {
        self.firstPage = firstPage
        self.lastPage = lastPage
        self.sessions = sessions
    }
}
