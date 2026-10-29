import FolioDomain
import Foundation

public enum ClaudeTask: String, Codable, Sendable, CaseIterable {
    case chat, reviewNoteDraft, examSummaryDraft, quizCards, grading, classifyFile, extractAssignment, extractGradingPolicy, examPlan, widget
}

/// Per the spec: light jobs (file classification) on the small model, grading and proof review on the large one.
/// Defaults are defined here only; settings may override per task.
public struct TaskConfig: Codable, Sendable, Equatable {
    public var model: String
    public var effort: Effort
    public var maxTokens: Int

    public static let large = "claude-opus-5-5"
    public static let small = "claude-haiku-5-5"

    public static func defaults(for task: ClaudeTask) -> TaskConfig {
        switch task {
        case .classifyFile, .extractAssignment: TaskConfig(model: small, effort: .low, maxTokens: 4_000)
        case .grading: TaskConfig(model: large, effort: .high, maxTokens: 16_000)
        case .chat, .reviewNoteDraft, .examSummaryDraft, .quizCards, .extractGradingPolicy, .examPlan, .widget:
            TaskConfig(model: large, effort: .medium, maxTokens: 16_000)
        }
    }

    /// Server-side refusal fallback exists for the Opus line, not for Haiku.
    var supportsFallback: Bool { model.hasPrefix("claude-opus") }
}

/// $ per million tokens. Cache writes are billed at 1.25× input; reads at the listed rate.
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

    public init(provider: any ClaudeProvider, overrides: [ClaudeTask: TaskConfig] = [:], onUsage: @escaping @Sendable (APIUsageEvent) -> Void = { _ in }) {
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

    /// Refusals and truncation throw instead of returning partial text.
    public func text(_ task: ClaudeTask, system: [ContentBlock], messages: [Message],
                     onText: (@Sendable (String) -> Void)? = nil) async throws -> MessagesResponse {
        try await send(task, request(task, system: system, messages: messages), onText: onText)
    }

    /// A reply that doesn't decode is asked for once more, then reported
    /// (docs/SPEC.md "스키마에 맞지 않는 응답은 한 번 다시 요청").
    public func structured<T: Decodable & Sendable>(_ task: ClaudeTask, as _: T.Type, schema: JSONValue,
                                                    system: [ContentBlock], messages: [Message]) async throws -> T {
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

    func send(_ task: ClaudeTask, _ request: MessagesRequest, onText: (@Sendable (String) -> Void)? = nil) async throws -> MessagesResponse {
        let response = if let onText { try await provider.send(request, onText: onText) } else { try await provider.send(request) }
        onUsage(APIUsageEvent(task: task, model: response.model, usage: response.usage))
        switch response.stop_reason {
        case "refusal": throw ClaudeError.refused
        case "max_tokens": throw ClaudeError.truncated
        default: return response
        }
    }
}
