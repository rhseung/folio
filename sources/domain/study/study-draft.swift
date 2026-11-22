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
