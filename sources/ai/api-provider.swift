import Foundation

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
