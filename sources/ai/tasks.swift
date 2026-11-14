import FolioDomain
import Foundation

public enum ClaudeTask: String, Codable, Sendable, CaseIterable {
    case chat, reviewNoteDraft, examSummaryDraft, quizCards, grading, classifyFile, extractAssignment, extractGradingPolicy, examPlan,
        widget, lectureSections
}

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

public struct ModelPricing: Sendable, Equatable {
    public var input: Double
    public var output: Double
    public var cacheRead: Double

    public static let table: [String: ModelPricing] = [
        "claude-opus-5-5": ModelPricing(input: 4, output: 20, cacheRead: 0.2),
        "claude-haiku-5-5": ModelPricing(input: 0.1, output: 0.5, cacheRead: 0.01),
    ]

    public func cost(of usage: Usage) -> Double {
        let write = Double(usage.cache_creation_input_tokens ?? 0) * input * 1.25
        let read = Double(usage.cache_read_input_tokens ?? 0) * cacheRead
        return (Double(usage.input_tokens) * input + Double(usage.output_tokens) * output + write + read) / 1_000_000
    }
}

public struct APIUsageEvent: LogEvent, Equatable {
    public static let type = "api_usage"
    public var task: ClaudeTask
    public var model: String
    public var usage: Usage

    public var cost: Double? { ModelPricing.table[model]?.cost(of: usage) }
}

public struct ClaudeClient: Sendable {
    let provider: any ClaudeProvider
    let configs: [ClaudeTask: TaskConfig]
    let onUsage: @Sendable (APIUsageEvent) -> Void

    public init(
        provider: any ClaudeProvider, overrides: [ClaudeTask: TaskConfig] = [:],
        onUsage: @escaping @Sendable (APIUsageEvent) -> Void = { _ in }
    ) {
        self.provider = provider
        self.configs = overrides
        self.onUsage = onUsage
    }

    func config(_ task: ClaudeTask) -> TaskConfig {
        configs[task] ?? TaskConfig.defaults(for: task)
    }

    func request(_ task: ClaudeTask, system: [ContentBlock], messages: [Message], schema: JSONValue? = nil) -> MessagesRequest {
        let c = config(task)
        return MessagesRequest(
            model: c.model, max_tokens: c.maxTokens, system: system.isEmpty ? nil : system, messages: messages,
            output_config: OutputConfig(effort: c.effort, format: schema.map { OutputConfig.Format(schema: $0) }),
            fallbacks: c.supportsFallback ? "default" : nil
        )
    }

    public func text(
        _ task: ClaudeTask, system: [ContentBlock], messages: [Message],
        onEvent: (@Sendable (StreamEvent) -> Void)? = nil
    ) async throws -> MessagesResponse {
        try await send(task, request(task, system: system, messages: messages), onEvent: onEvent)
    }

    public func structured<T: Decodable & Sendable>(
        _ task: ClaudeTask, as _: T.Type, schema: JSONValue,
        system: [ContentBlock], messages: [Message]
    ) async throws -> T {
        let req = request(task, system: system, messages: messages, schema: schema)
        var lastError = ""
        for _ in 0..<2 {
            let response = try await send(task, req)
            do {
                return try JSONDecoder().decode(T.self, from: Data(response.text.utf8))
            } catch {
                lastError = String(describing: error)
            }
        }
        throw ClaudeError.invalidOutput(lastError)
    }

    func send(_ task: ClaudeTask, _ request: MessagesRequest, onEvent: (@Sendable (StreamEvent) -> Void)? = nil) async throws
        -> MessagesResponse
    {
        let response = if let onEvent { try await provider.send(request, onEvent: onEvent) } else { try await provider.send(request) }
        onUsage(APIUsageEvent(task: task, model: response.model, usage: response.usage))
        switch response.stop_reason {
        case "refusal": throw ClaudeError.refused
        case "max_tokens": throw ClaudeError.truncated
        default: return response
        }
    }
}
