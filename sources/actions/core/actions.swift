import FolioDomain

public enum Actions {
    // 목록 `all`은 folio-gen이 sources/actions의 선언에서 만든다(generated/actions-all.swift).
    public static let targets: [String: ProposalTarget] = {
        func arguments(_ type: any Action.Type) -> [String] { type.spec.fields.filter { $0.role == .argument }.map(\.name) }
        var targets = Dictionary(
            all.compactMap { type -> (String, ProposalTarget)? in
                let values = type.spec.fields.filter { $0.role != .argument }
                guard type.spec.effect == .changes, !values.isEmpty, values.allSatisfy(\.patch) else { return nil }
                return (type.command, ProposalTarget(arguments: arguments(type), effect: .sets))
            }, uniquingKeysWith: { a, _ in a })

        // spec으로는 이 액션들을 덧붙이는 `note edit`와 구분할 수 없다. 필드가 `Patch`가 아니라 맨 값이기 때문이다. 다시
        // 쓰기는 같은 파일의 앞선 다시 쓰기나 편집을 아무것도 남기지 않는다. `note link`는 종류와 링크를 쓰고 빠진 링크를
        // 지우므로, 빠진 링크를 남기는 것으로 다뤄도 앞선 제안을 덜 대체할 뿐이다.
        targets[NoteWrite.command] = ProposalTarget(arguments: arguments(NoteWrite.self), effect: .replaces(covers: [NoteEdit.command]))
        targets[MaterialWrite.command] = ProposalTarget(arguments: arguments(MaterialWrite.self), effect: .replaces(covers: []))
        targets[NoteFigureWrite.command] = ProposalTarget(arguments: arguments(NoteFigureWrite.self), effect: .replaces(covers: []))
        targets[NoteWidgetWrite.command] = ProposalTarget(arguments: arguments(NoteWidgetWrite.self), effect: .replaces(covers: []))
        targets[NoteLink.command] = ProposalTarget(arguments: arguments(NoteLink.self), effect: .sets)
        return targets
    }()
}
