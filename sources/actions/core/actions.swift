import FolioDomain
import FolioStorage
import Foundation

public enum Actions {
    // 목록 `all`은 folio-gen이 sources/actions의 선언에서 만든다(generated/actions-all.swift).
    public static let targets: [String: ProposalTarget] = Dictionary(
        all.compactMap { type -> (String, ProposalTarget)? in
            let spec = type.spec
            let arguments = spec.fields.filter { $0.role == .argument }.map(\.name)
            if let effect = spec.proposal { return (type.command, ProposalTarget(arguments: arguments, effect: effect)) }
            let values = spec.fields.filter { $0.role != .argument }
            guard spec.effect == .changes, !values.isEmpty, values.allSatisfy(\.patch) else { return nil }
            return (type.command, ProposalTarget(arguments: arguments, effect: .sets))
        }, uniquingKeysWith: { a, _ in a })
}

extension Actions {
    // 제안의 명령과 입력을 그 액션 값으로 읽는다. 이 Folio가 모르는 명령이나 맞지 않는 입력이면 nil이다.
    public static func action(_ proposal: ActionProposal) -> (any Action)? {
        guard let type = all.first(where: { $0.command == proposal.command }) else { return nil }
        return try? decode(type, proposal.input)
    }

    private static func decode<A: Action>(_ type: A.Type, _ input: JSONValue) throws -> A {
        try JSONDecoder.folio.decode(A.self, from: JSONEncoder().encode(input))
    }

    public static func summary(_ proposal: ActionProposal, ctx: ActionContext) -> String? {
        action(proposal).map { summary($0, ctx: ctx) }
    }

    static func summary<A: Action>(_ action: A, ctx: ActionContext) -> String { A.spec.render(A.spec.done, action, ctx: ctx) }
}
