import Foundation

/// Where requests go: `CLIProvider` (Mac, the user's Claude Code subscription), `APIProvider` (both platforms),
/// and `FakeProvider` in tests.
public protocol ClaudeProvider: Sendable {
    func send(_ request: MessagesRequest) async throws -> MessagesResponse
    func send(_ request: MessagesRequest, onText: @escaping @Sendable (String) -> Void) async throws -> MessagesResponse
}

extension ClaudeProvider {
    // shortcut: the API provider answers all at once; give it SSE streaming if API-key users find the wait too blank.
    public func send(_ request: MessagesRequest, onText: @escaping @Sendable (String) -> Void) async throws -> MessagesResponse {
        try await send(request)
    }
}

public struct APIProvider: ClaudeProvider {
    let apiKey: @Sendable () -> String?
    let session: URLSession
    let maxRetries: Int

    public init(apiKey: @escaping @Sendable () -> String?, session: URLSession = .shared, maxRetries: Int = 2) {
        self.apiKey = apiKey
        self.session = session
        self.maxRetries = maxRetries
    }

    func urlRequest(for request: MessagesRequest) throws -> URLRequest {
        guard let key = apiKey(), !key.isEmpty else { throw ClaudeError.missingAPIKey }
        var r = URLRequest(url: ClaudeAPI.endpoint)
        r.httpMethod = "POST"
        r.timeoutInterval = 600
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        r.setValue(key, forHTTPHeaderField: "x-api-key")
        r.setValue(ClaudeAPI.version, forHTTPHeaderField: "anthropic-version")
        if !request.betas.isEmpty { r.setValue(request.betas.joined(separator: ","), forHTTPHeaderField: "anthropic-beta") }
        r.httpBody = try JSONEncoder().encode(request)
        return r
    }

    public func send(_ request: MessagesRequest) async throws -> MessagesResponse {
        let urlRequest = try urlRequest(for: request)
        var attempt = 0
        while true {
            let (data, response) = try await session.data(for: urlRequest)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 { return try JSONDecoder().decode(MessagesResponse.self, from: data) }
            let retryable = status == 429 || status >= 500
            guard retryable, attempt < maxRetries else {
                throw ClaudeError.http(status: status, body: String(decoding: data, as: UTF8.self))
            }
            attempt += 1
            let after = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "retry-after").flatMap(Double.init) ?? Double(attempt * 2)
            try await Task.sleep(for: .seconds(min(after, 30)))
        }
    }
}

public actor FakeProvider: ClaudeProvider {
    public private(set) var requests: [MessagesRequest] = []
    var responses: [MessagesResponse]

    public init(responses: [MessagesResponse]) {
        self.responses = responses
    }

    public func send(_ request: MessagesRequest) async throws -> MessagesResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw ClaudeError.http(status: 500, body: "FakeProvider has no response left") }
        return responses.removeFirst()
    }

    public static func reply(_ text: String, model: String = "claude-opus-5-5", stop: String = "end_turn") -> MessagesResponse {
        MessagesResponse(id: "msg_fake", model: model, content: [.text(text)], stop_reason: stop, usage: Usage(input_tokens: 10, output_tokens: 5))
    }
}
