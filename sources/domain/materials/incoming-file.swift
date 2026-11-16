import Foundation

public struct IncomingFile: Equatable, Sendable {
    public var name: String
    public var pages: Int?
    public var landscape: Bool

    public init(name: String, pages: Int? = nil, landscape: Bool = false) {
        (self.name, self.pages, self.landscape) = (name, pages, landscape)
    }
}
