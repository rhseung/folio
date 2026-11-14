import Foundation

public struct QuizCard: Entity {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var updatedBy: DeviceID

    public var unitId: UUID
    public var type: CardType
    public var category: CardCategory
    public var prompt: String
    public var figure: String?
    public var options: [String]
    public var answer: String
    public var rubric: [String]
    public var source: CardSource
    public var sourceMaterialId: UUID?
    public var sourceProblem: String?
    public var noteId: UUID?
    public var noteBlockId: String?
    public var noteBlockHash: String?

    public init(
        id: UUID = UUID(), device: DeviceID, at date: Date, unitId: UUID, type: CardType, category: CardCategory,
        prompt: String, options: [String] = [], answer: String, rubric: [String] = [], source: CardSource = .manual
    ) {
        self.id = id
        self.createdAt = date
        self.updatedAt = date
        self.updatedBy = device
        self.unitId = unitId
        self.type = type
        self.category = category
        self.prompt = prompt
        self.options = options
        self.answer = answer
        self.rubric = rubric
        self.source = source
    }
}
