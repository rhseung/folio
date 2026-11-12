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
    /// The earlier proposals of the same answer it was made on top of, by their place in the answer: the panel's
    /// server runs an answer's proposals one after another in a staged copy, and this one failed against the folder
    /// alone. Until those are applied it can't be.
    public var after: [Int]?

    public init(command: String, input: JSONValue, applied: Bool? = nil, failure: String? = nil, after: [Int]? = nil) {
        self.command = command
        self.input = input
        self.applied = applied
        self.failure = failure
        self.after = after
    }

    /// Whether a command's proposal also runs for real in a staged copy of the folder (`StagedFolder`), so later ones
    /// build on it: the panel's server does this as it proposes, and the panel again when it checks a chain before
    /// applying it. These groups write outside the GIST folder (a backup, cleanup's backup copy, an import's source)
    /// or rewrite audio, which the copy's fence only covers for coordinated writes, so they stay dry runs there.
    public static func stages(_ command: String) -> Bool {
        command.split(separator: " ").first.map { !unstaged.contains(String($0)) } ?? false
    }

    static let unstaged: Set<String> = ["backup", "cleanup", "import", "recording"]

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

/// How a command's proposal stands to an earlier one for the same item: whether applying it leaves anything of the
/// earlier one. A command without one only adds (a note edit's append, a new exam, a log entry) and never stands in
/// for another proposal.
public struct ProposalTarget: Sendable, Equatable {
    public enum Effect: Sendable, Equatable {
        /// Writes the item whole, so nothing of an earlier proposal of this command or of `covers` is left.
        case replaces(covers: Set<String>)
        /// Writes the fields present in its input; a field left out stays as it is.
        case sets
    }

    /// The fields that pick the item, the action's `@Arg` fields.
    public var arguments: [String]
    public var effect: Effect

    public init(arguments: [String], effect: Effect) {
        self.arguments = arguments
        self.effect = effect
    }

    /// Whether applying `later` (of this target's command) after `earlier` leaves nothing `earlier` would change.
    public func overrides(_ earlier: ActionProposal, with later: ActionProposal) -> Bool {
        guard let item = later.target(arguments), earlier.target(arguments) == item else { return false }
        switch effect {
        case .replaces(let covers):
            return earlier.command == later.command || covers.contains(earlier.command)
        case .sets:
            // A field absent from the input is left as it is (`Patch.keep`, a nil optional); `null` clears it, so it counts.
            func fields(_ p: ActionProposal) -> Set<String> {
                guard case .object(let o) = p.input else { return [] }
                return Set(o.keys).subtracting(arguments)
            }
            return earlier.command == later.command && fields(earlier).isSubset(of: fields(later))
        }
    }
}

extension Chat {
    /// Pending proposals that a later answer made pointless: applying the later one would write over everything the
    /// earlier one changes, so applying the earlier after it would only undo it. Proposals of one answer are separate
    /// changes and never supersede each other. `targets` maps a command to how it stands to earlier proposals; a
    /// command missing from it supersedes nothing.
    public func supersededProposals(targets: [String: ProposalTarget]) -> Set<ProposalRef> {
        var superseded = Set<ProposalRef>()
        for (m, message) in messages.enumerated() {
            let later = messages[(m + 1)...].flatMap { $0.proposals ?? [] }.compactMap { p in targets[p.command].map { (p, $0) } }
            for (i, p) in (message.proposals ?? []).enumerated() where p.applied != true {
                if later.contains(where: { q, target in target.overrides(p, with: q) }) { superseded.insert(ProposalRef(message: message.id, index: i)) }
            }
        }
        return superseded
    }
}

extension ChatMessage {
    /// Why the proposal at `index` waits on earlier ones of this answer: some it was made on top of are not applied
    /// yet (`earlier`), or one of those can no longer be, which blocks it too (`blocked`). Nil when it stands alone.
    public enum Waiting: Equatable, Sendable {
        case earlier([Int])
        case blocked([Int])
    }

    /// `refused` says whether a proposal can't be applied on its own now (superseded, or its dry run refuses). An
    /// earlier one that is refused only because it waits on others is still waiting, not dead.
    public func waiting(_ index: Int, refused: (Int) -> Bool) -> Waiting? {
        guard let proposals, proposals.indices.contains(index) else { return nil }
        let pending = Set(proposals[index].after ?? []).filter { $0 < index && $0 >= 0 && proposals[$0].applied != true }.sorted()
        guard !pending.isEmpty else { return nil }
        let dead = pending.filter { j in
            guard refused(j) else { return false }
            if case .earlier? = waiting(j, refused: refused) { return false }
            return true
        }
        return dead.isEmpty ? .earlier(pending) : .blocked(dead)
    }
}
