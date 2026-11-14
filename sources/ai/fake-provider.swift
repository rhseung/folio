import Foundation

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
        MessagesResponse(
            id: "msg_fake", model: model, content: [.text(text)], stop_reason: stop, usage: Usage(input_tokens: 10, output_tokens: 5))
    }
}
