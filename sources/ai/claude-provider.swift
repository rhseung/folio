import Foundation

public protocol ClaudeProvider: Sendable {
    func send(_ request: MessagesRequest) async throws -> MessagesResponse
    func send(_ request: MessagesRequest, onEvent: @escaping @Sendable (StreamEvent) -> Void) async throws -> MessagesResponse
}

extension ClaudeProvider {
    // shortcut: API 프로바이더는 답을 한 번에 돌려준다. API 키 사용자가 기다리는 동안 화면이 너무 비어 보인다고 하면
    // SSE streaming을 붙인다.
    public func send(_ request: MessagesRequest, onEvent: @escaping @Sendable (StreamEvent) -> Void) async throws -> MessagesResponse {
        try await send(request)
    }
}
