import FolioCore
import Foundation

// Claude가 만든 공부 자료(뽑은 문제, 제안한 카드, 만든 문제지)다. 받기 전에는 course.json을 바꾸지 않고
// `.folio/drafts`에만 두므로, 받기 전까지 사용자가 고칠 수 있고 버려도 과목에 흔적이 남지 않는다.
public struct StudyDraft: Entity {
    public enum Kind: String, Codable, Sendable {
        case problems
        case cards
        case sheet
    }

    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var updatedBy: DeviceID

    public var kind: Kind
    public var title: String
    public var materialId: UUID?
    public var unitIds: [UUID]
    // 받으면 실행하는 액션이다. 받은 뒤에는 `applied`가 참이 되어 다시 실행하지 않는다.
    public var proposal: ActionProposal

    public init(
        id: UUID = UUID(), device: DeviceID, at date: Date, kind: Kind, title: String, materialId: UUID? = nil, unitIds: [UUID] = [],
        proposal: ActionProposal
    ) {
        self.id = id
        createdAt = date
        updatedAt = date
        updatedBy = device
        self.kind = kind
        self.title = title
        self.materialId = materialId
        self.unitIds = unitIds
        self.proposal = proposal
    }

    public var isApplied: Bool { proposal.applied == true }
}

extension StudyDraft {
    // 문제 초안의 문제는 받으면 실행할 `problem-set add` 입력의 `problems`에 있다. 따로 두면 검토에서 고친 문제와 받을 때
    // 실행하는 입력이 어긋난다.
    public var problems: [Problem] {
        get {
            guard let value = proposal.input["problems"], let data = try? JSONEncoder().encode(value) else { return [] }
            return (try? JSONDecoder().decode([Problem].self, from: data)) ?? []
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue), let value = try? JSONDecoder().decode(JSONValue.self, from: data) else {
                return
            }
            proposal.input["problems"] = value
        }
    }

    public var solutionMaterialId: UUID? {
        if case .string(let s)? = proposal.input["solution"] { return UUID(uuidString: s) }
        return nil
    }
}
