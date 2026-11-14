import Foundation

public struct ExamPlanItem: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var day: LocalDate
    public var title: String
    public var target: ExamPlanTarget?

    public init(id: UUID = UUID(), day: LocalDate, title: String, target: ExamPlanTarget? = nil) {
        self.id = id
        self.day = day
        self.title = title
        self.target = target
    }
}
