import Foundation

public struct ActionProposal: Codable, Hashable, Sendable {
    public var command: String
    public var input: JSONValue
    public var applied: Bool?
    public var failure: String?
    public var after: [Int]?

    public init(command: String, input: JSONValue, applied: Bool? = nil, failure: String? = nil, after: [Int]? = nil) {
        self.command = command
        self.input = input
        self.applied = applied
        self.failure = failure
        self.after = after
    }

    // 이 그룹은 GIST 폴더 밖에 쓰거나(백업, 정리의 백업 사본, 가져오기의 원본) 오디오를 다시 쓴다. 사본의 쓰기
    // 제한은 조정된 쓰기만 막으므로, 이 그룹은 사본에서도 미리 실행만 한다.
    public static func stages(_ command: String) -> Bool {
        command.split(separator: " ").first.map { !unstaged.contains(String($0)) } ?? false
    }

    static let unstaged: Set<String> = ["backup", "cleanup", "import", "recording"]

    public static let marker = "folio-proposal:"

    public var text: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return Self.marker + String(decoding: (try? encoder.encode(self)) ?? Data(), as: UTF8.self)
    }

    public init?(text: String) {
        guard text.hasPrefix(Self.marker),
            let p = try? JSONDecoder().decode(Self.self, from: Data(text.dropFirst(Self.marker.count).utf8))
        else { return nil }
        self = p
    }

    // 인자가 없는 변경을 다른 변경으로 잘못 보지 않도록, 인자가 없으면 nil을 돌려준다.
    public func target(_ arguments: [String]) -> JSONValue? {
        guard !arguments.isEmpty else { return nil }
        return .object(Dictionary(uniqueKeysWithValues: arguments.map { ($0, input[$0] ?? .null) }))
    }
}

public struct ProposalRef: Hashable, Sendable {
    public var message: UUID
    public var index: Int

    public init(message: UUID, index: Int) {
        self.message = message
        self.index = index
    }
}

public struct ProposalTarget: Sendable, Equatable {
    public enum Effect: Sendable, Equatable {
        case replaces(covers: Set<String>)
        case sets
    }

    public var arguments: [String]
    public var effect: Effect

    public init(arguments: [String], effect: Effect) {
        self.arguments = arguments
        self.effect = effect
    }

    public func overrides(_ earlier: ActionProposal, with later: ActionProposal) -> Bool {
        guard let item = later.target(arguments), earlier.target(arguments) == item else { return false }
        switch effect {
        case .replaces(let covers):
            return earlier.command == later.command || covers.contains(earlier.command)
        case .sets:
            // 입력에 없는 필드는 그대로 남는다(`Patch.keep`, nil인 옵셔널). `null`은 값을 지우므로 바꾼 필드로 센다.
            func fields(_ p: ActionProposal) -> Set<String> {
                guard case .object(let o) = p.input else { return [] }
                return Set(o.keys).subtracting(arguments)
            }
            return earlier.command == later.command && fields(earlier).isSubset(of: fields(later))
        }
    }
}

extension Chat {
    public func supersededProposals(targets: [String: ProposalTarget]) -> Set<ProposalRef> {
        var superseded = Set<ProposalRef>()
        for (m, message) in messages.enumerated() {
            let later = messages[(m + 1)...].flatMap { $0.proposals ?? [] }.compactMap { p in targets[p.command].map { (p, $0) } }
            for (i, p) in (message.proposals ?? []).enumerated() where p.applied != true {
                if later.contains(where: { q, target in target.overrides(p, with: q) }) {
                    superseded.insert(ProposalRef(message: message.id, index: i))
                }
            }
        }
        return superseded
    }
}

extension ChatMessage {
    public enum Waiting: Equatable, Sendable {
        case earlier([Int])
        case blocked([Int])
    }

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
