import Foundation

public struct TrackingIO {
    public var resolveBookmark: (Material) -> String?
    public var hash: (String) throws -> String?
    public var makeBookmark: (String) -> Data?

    public init(
        resolveBookmark: @escaping (Material) -> String?,
        hash: @escaping (String) throws -> String?,
        makeBookmark: @escaping (String) -> Data?
    ) {
        self.resolveBookmark = resolveBookmark
        self.hash = hash
        self.makeBookmark = makeBookmark
    }
}
