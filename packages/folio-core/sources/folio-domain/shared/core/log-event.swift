/// A record appended to a device log. `type` is the stored discriminator and must never change.
public protocol LogEvent: Codable, Sendable {
    static var type: String { get }
}
