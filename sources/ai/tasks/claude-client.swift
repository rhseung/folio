import FolioDomain
import Foundation

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
