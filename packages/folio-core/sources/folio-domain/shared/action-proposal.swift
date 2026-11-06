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

    /// The item the change is about: the values of `arguments` (the action's `@Arg` fields) in its input. Nil without
    /// arguments, so such a change is never taken for another.
    public func target(_ arguments: [String]) -> JSONValue? {
        guard !arguments.isEmpty else { return nil }
        return .object(Dictionary(uniqueKeysWithValues: arguments.map { ($0, input[$0] ?? .null) }))
    }
}

/// One proposal in a chat: the answer it came with and its place among that answer's proposals.
public struct ProposalRef: Hashable, Sendable {
    public var message: UUID
    public var index: Int

    public init(message: UUID, index: Int) {
        self.message = message
        self.index = index
    }
}

extension Chat {
    /// Pending proposals that a later answer proposed again for the same item with the same command. Applying the
    /// older one after the newer would undo or repeat it, so only the newest is offered. `arguments` maps a command to
    /// the fields that pick its item; a command missing from it is never superseded.
    public func supersededProposals(arguments: [String: [String]]) -> Set<ProposalRef> {
        struct Key: Hashable {
            var command: String
            var target: JSONValue
        }
        func key(_ p: ActionProposal) -> Key? {
            arguments[p.command].flatMap { p.target($0) }.map { Key(command: p.command, target: $0) }
        }
        var later = Set<Key>()
        var superseded = Set<ProposalRef>()
        for message in messages.reversed() {
            let proposals = message.proposals ?? []
            for (i, p) in proposals.enumerated() where p.applied != true {
                if let k = key(p), later.contains(k) { superseded.insert(ProposalRef(message: message.id, index: i)) }
            }
            // Added after the check: the proposals of one answer are separate changes, not versions of each other.
            later.formUnion(proposals.compactMap(key))
        }
        return superseded
    }
}
