import FolioDomain
import Foundation

public struct LoggedEvent: Sendable, Equatable {
    public var id: UUID
    public var at: Date
    public var device: DeviceID
    public var type: String
    public var data: JSONValue

    public func decode<E: LogEvent>(_: E.Type) throws -> E? {
        guard type == E.type else { return nil }
        return try JSONFormat.decoder.decode(E.self, from: JSONFormat.encoder.encode(data))
    }
}
