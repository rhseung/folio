import Foundation

/// A change Claude asked for through `folio mcp --propose`: previewed, not made, until the user approves it in the
/// panel. `input` already names every item by UUID, so the app can decode the action without looking names up.
public struct ActionProposal: Codable, Hashable, Sendable {
    public var command: String
    public var input: JSONValue
    /// Set once the user applies it, so the chat shows it done instead of offering it again.
    public var applied: Bool?
    /// Why it failed the last time the user applied it. Kept in the chat so the next question tells Claude, which
    /// otherwise can only guess whether its change went through.
    public var failure: String?

    public init(command: String, input: JSONValue, applied: Bool? = nil, failure: String? = nil) {
        self.command = command
        self.input = input
        self.applied = applied
        self.failure = failure
    }

    /// Starts the tool-result text block that carries the proposal, apart from the preview text beside it.
    public static let marker = "folio-proposal:"

    public var text: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return Self.marker + String(decoding: (try? encoder.encode(self)) ?? Data(), as: UTF8.self)
    }

    public init?(text: String) {
        guard text.hasPrefix(Self.marker),
              let p = try? JSONDecoder().decode(Self.self, from: Data(text.dropFirst(Self.marker.count).utf8)) else { return nil }
        self = p
    }
}
