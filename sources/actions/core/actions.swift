import FolioDomain

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
