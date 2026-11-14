import FolioDomain
import Foundation

public struct TaskConfig: Codable, Sendable, Equatable {
    public var model: String
    public var effort: Effort
    public var maxTokens: Int

    public static let large = "claude-opus-5-5"
    public static let small = "claude-haiku-5-5"

    public static func defaults(for task: ClaudeTask) -> TaskConfig {
        switch task {
        case .classifyFile, .extractAssignment: TaskConfig(model: small, effort: .low, maxTokens: 4_000)
        // 모든 쪽의 글을 읽으므로 107쪽 덱이면 약 20k token이다. low에서 작은 모델은 경계 몇 개를 한 슬라이드씩
        // 어긋나게 잡았고, medium에서는 큰 모델과 같은 경계를 30분의 1 비용으로 잡았다.
        case .lectureSections: TaskConfig(model: small, effort: .medium, maxTokens: 8_000)
        case .grading: TaskConfig(model: large, effort: .high, maxTokens: 16_000)
        case .chat, .reviewNoteDraft, .examSummaryDraft, .quizCards, .extractGradingPolicy, .examPlan, .widget:
            TaskConfig(model: large, effort: .medium, maxTokens: 16_000)
        }
    }

    var supportsFallback: Bool { model.hasPrefix("claude-opus") }
}
