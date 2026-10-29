@testable import FolioAI
import FolioDomain
import Foundation
import Testing

/// Captures the outgoing request and answers with a canned response.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var captured: URLRequest?
    nonisolated(unsafe) static var body: Data?
    nonisolated(unsafe) static var reply: (Int, Data) = (200, Data())

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.captured = request
        Self.body = request.httpBody ?? request.httpBodyStream.map { stream in
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; data.append(buffer, count: n) }
            return data
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.reply.0, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.reply.1)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized)
struct APIProviderTests {
    func provider() -> APIProvider {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return APIProvider(apiKey: { "sk-test" }, session: URLSession(configuration: config), maxRetries: 0)
    }

    @Test func sendsDocumentedHeadersAndBody() async throws {
        StubProtocol.reply = (200, Data(#"{"id":"msg_1","model":"claude-opus-5-5","content":[{"type":"thinking","thinking":""},{"type":"text","text":"안녕"}],"stop_reason":"end_turn","usage":{"input_tokens":12,"output_tokens":3,"cache_read_input_tokens":100}}"#.utf8))
        let client = ClaudeClient(provider: provider())
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        let response = try await client.text(.chat, system: [.text("과목 요약", cache: true)],
                                             messages: [Message(role: .user, content: [.image(png, mediaType: "image/png"), .text("질문")])])
        #expect(response.text == "안녕")
        #expect(response.usage.cache_read_input_tokens == 100)

        let r = try #require(StubProtocol.captured)
        #expect(r.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(r.value(forHTTPHeaderField: "x-api-key") == "sk-test")
        #expect(r.value(forHTTPHeaderField: "anthropic-version") == "2026-10-21")
        #expect(r.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01")

        let body = try JSONDecoder().decode(JSONValue.self, from: try #require(StubProtocol.body))
        #expect(body["model"] == .string("claude-opus-5-5"))
        #expect(body["fallbacks"] == .string("default"))
        #expect(body["output_config"]?["effort"] == .string("medium"))
        #expect(body["temperature"] == nil && body["thinking"] == nil)
        guard case .array(let system)? = body["system"], case .array(let messages)? = body["messages"],
              case .array(let content)? = messages.first?["content"] else { Issue.record("shape"); return }
        #expect(system.first?["cache_control"]?["type"] == .string("ephemeral"))
        #expect(content.first?["source"]?["data"] == .string(png.base64EncodedString()))
        #expect(content.first?["source"]?["media_type"] == .string("image/png"))
    }

    @Test func haikuTasksSkipTheFallback() async throws {
        StubProtocol.reply = (200, Data(#"{"id":"m","model":"claude-haiku-5-5","content":[{"type":"text","text":"{\"title\":\"HW5\",\"due\":null}"}],"stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1}}"#.utf8))
        let result = try await ClaudeClient(provider: provider()).run(.extractAssignment, AssignmentExtraction.self, system: [], messages: [Message(role: .user, content: [.text("pdf")])])
        #expect(result == AssignmentExtraction(title: "HW5", due: nil))
        let body = try JSONDecoder().decode(JSONValue.self, from: try #require(StubProtocol.body))
        #expect(body["model"] == .string("claude-haiku-5-5") && body["fallbacks"] == nil)
        #expect(body["output_config"]?["format"]?["type"] == .string("json_schema"))
        #expect(StubProtocol.captured?.value(forHTTPHeaderField: "anthropic-beta") == nil)
    }

    @Test func httpErrorsSurfaceWithBody() async {
        StubProtocol.reply = (400, Data(#"{"type":"error"}"#.utf8))
        await #expect(throws: ClaudeError.http(status: 400, body: #"{"type":"error"}"#)) {
            try await ClaudeClient(provider: provider()).text(.chat, system: [], messages: [])
        }
    }

    @Test func missingKey() async {
        let p = APIProvider(apiKey: { nil })
        await #expect(throws: ClaudeError.missingAPIKey) { try await p.send(ClaudeClient(provider: p).request(.chat, system: [], messages: [])) }
    }
}

struct ClaudeClientTests {
    @Test func refusalAndTruncationNeverReturnContent() async {
        let refused = ClaudeClient(provider: FakeProvider(responses: [FakeProvider.reply("partial", stop: "refusal")]))
        await #expect(throws: ClaudeError.refused) { try await refused.text(.chat, system: [], messages: []) }
        let cut = ClaudeClient(provider: FakeProvider(responses: [FakeProvider.reply("half", stop: "max_tokens")]))
        await #expect(throws: ClaudeError.truncated) { try await cut.text(.chat, system: [], messages: []) }
    }

    @Test func schemaMismatchIsRetriedOnceThenReported() async throws {
        let good = #"{"verdict":"partial","missing":["귀납 가정"],"feedback":"가정을 쓰세요.","lines":[{"line":3,"note":"비약"}]}"#
        let fake = FakeProvider(responses: [FakeProvider.reply("not json"), FakeProvider.reply(good)])
        let result = try await ClaudeClient(provider: fake).grade(question: "Q", modelAnswer: "A", rubric: ["귀납 가정"], answer: "x", rules: "")
        #expect(result.verdict == .partial && result.lines.first?.line == 3)
        #expect(await fake.requests.count == 2)
        #expect(await fake.requests.first?.output_config?.effort == .high)

        let bad = FakeProvider(responses: [FakeProvider.reply("nope"), FakeProvider.reply("still nope")])
        await #expect(throws: ClaudeError.self) {
            try await ClaudeClient(provider: bad).run(.grading, GradingResult.self, system: [], messages: [])
        }
    }

    @Test func usageIsReportedWithCost() async throws {
        let seen = UsageSink()
        let client = ClaudeClient(provider: FakeProvider(responses: [FakeProvider.reply("hi")]), onUsage: { e in Task { await seen.add(e) } })
        _ = try await client.text(.chat, system: [], messages: [])
        try await Task.sleep(for: .milliseconds(50))
        let events = await seen.events
        #expect(events.first?.task == .chat)
        #expect(events.first?.cost == 140.0 / 1_000_000)
    }

    @Test func overridesReplaceDefaults() async throws {
        let fake = FakeProvider(responses: [FakeProvider.reply("ok")])
        let client = ClaudeClient(provider: fake, overrides: [.chat: TaskConfig(model: "claude-haiku-5-5", effort: .low, maxTokens: 500)])
        _ = try await client.text(.chat, system: [], messages: [])
        let r = try #require(await fake.requests.first)
        #expect(r.model == "claude-haiku-5-5" && r.max_tokens == 500 && r.fallbacks == nil)
    }
}

actor UsageSink {
    var events: [APIUsageEvent] = []
    func add(_ e: APIUsageEvent) { events.append(e) }
}

struct ContextTests {
    @Test func dropsLaterTiersFirstAndCachesTheStablePart() {
        let items = [
            ContextItem(id: "s", title: "검색 결과", tier: .search, text: String(repeating: "가", count: 3000)),
            ContextItem(id: "c", title: "과목 요약", tier: .courseSummary, text: "그래프 이론"),
            ContextItem(id: "f", title: "현재 노트", tier: .focus, text: String(repeating: "나", count: 300)),
            ContextItem(id: "r", title: "규칙", tier: .userRules, text: "정의는 전제, 조건, 결론 순서로"),
        ]
        let built = ContextBuilder.build(items, budgetTokens: 200)
        #expect(built.included.map(\.id) == ["c", "r", "f"])
        #expect(built.dropped.map(\.id) == ["s"])
        guard case .text(let system, let cache)? = built.system.first else { Issue.record("no system"); return }
        #expect(cache && system.hasPrefix("<과목 요약>"))
        #expect(built.userBlocks.count == 1)
    }

    @Test func aNotesImagesFollowItsTextEachNamed() {
        let note = ContextItem(id: "n", title: "열린 노트: 9주차", tier: .focus, text: "![a](assets/a.jpg)",
                               images: [.init(name: "a.jpg", data: Data([1])), .init(name: "b.jpg", data: Data([2]))])
        let built = ContextBuilder.build([note], budgetTokens: 10_000)
        #expect(built.userBlocks == [.text("<열린 노트: 9주차>\n![a](assets/a.jpg)\n</열린 노트: 9주차>"),
                                     .text("열린 노트: 9주차의 그림 a.jpg:"), .image(Data([1]), mediaType: "image/jpeg"),
                                     .text("열린 노트: 9주차의 그림 b.jpg:"), .image(Data([2]), mediaType: "image/jpeg")])
        #expect(ContextBuilder.estimate(note) == 5_006)
    }

    @Test func courseSummaryIsStable() {
        let device = UUID(), now = Date(timeIntervalSince1970: 0)
        var file = CourseFile(course: Course(device: device, at: now, title: "그래프 이론", memo: "증명 위주"))
        file.units = [Unit(device: device, at: now, title: "Matchings", order: 2), Unit(device: device, at: now, title: "Trees", order: 1)]
        let a = ContextBuilder.courseSummary(file, now: now)
        #expect(a.text == "과목: 그래프 이론\n단원:\n- Trees\n- Matchings\n메모:\n증명 위주")
        #expect(a == ContextBuilder.courseSummary(file, now: now))
    }

    @Test func pricing() {
        let usage = Usage(input_tokens: 1_000_000, output_tokens: 100_000, cache_creation_input_tokens: 0, cache_read_input_tokens: 1_000_000)
        #expect(ModelPricing.table["claude-opus-5-5"]!.cost(of: usage) == 4 + 2 + 0.2)
    }

    @Test func schemasRequireEveryPropertyAndForbidExtras() {
        for schema in [GradingResult.schema, FileClassification.schema, AssignmentExtraction.schema, GradingPolicyExtraction.schema] {
            #expect(schema["additionalProperties"] == .bool(false))
            guard case .object(let props)? = schema["properties"], case .array(let required)? = schema["required"] else { Issue.record("shape"); continue }
            #expect(Set(required) == Set(props.keys.map(JSONValue.string)))
        }
    }
}

#if os(macOS)
struct CLIProviderTests {
    @Test func textDeltasComeFromPartialMessageLinesOnly() {
        let delta = #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"정리"}}}"#
        let thinking = #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"음"}}}"#
        let result = #"{"type":"result","result":"정리"}"#
        #expect(CLIProvider.textDelta(Data(delta.utf8)) == "정리")
        #expect(CLIProvider.textDelta(Data(thinking.utf8)) == nil && CLIProvider.textDelta(Data(result.utf8)) == nil)
    }

    let request = MessagesRequest(
        model: "claude-opus-5-5", max_tokens: 100, system: [.text("규칙")],
        messages: [Message(role: .user, content: [.text("첫 질문")]), Message(role: .assistant, content: [.text("첫 답")]),
                   Message(role: .user, content: [.text("두 번째 질문")])],
        output_config: OutputConfig(effort: .low, format: .init(schema: .object(["type": .string("object")]))))

    /// No tools: the CLI may only answer, never touch the GIST folder.
    @Test func runsWithoutToolsAndFoldsHistoryIntoOneMessage() throws {
        let args = try CLIProvider.arguments(for: request, systemFile: URL(fileURLWithPath: "/tmp/s.txt"))
        #expect(args.split(separator: "--tools").count == 2 && args[args.firstIndex(of: "--tools")! + 1] == "")
        #expect(args.contains("--system-prompt-file") && args.contains("--json-schema") && args.contains("low"))
        let line = try JSONDecoder().decode(JSONValue.self, from: CLIProvider.input(for: request))
        guard case .array(let content)? = line["message"]?["content"] else { Issue.record("no content"); return }
        #expect(content.count == 2)
        #expect(content[0]["text"] == .string("지금까지의 대화:\n\n사용자: 첫 질문\n\nClaude: 첫 답"))
        #expect(content[1]["text"] == .string("두 번째 질문"))
    }

    @Test func readsTheResultLine() throws {
        let ok = Data("""
            {"type":"system","subtype":"init"}
            {"type":"result","is_error":false,"stop_reason":"tool_use","result":"{}","structured_output":{"answer":2},"session_id":"s","usage":{"input_tokens":2,"output_tokens":5},"modelUsage":{"claude-haiku-5-5":{}}}
            """.utf8)
        let r = try CLIProvider.response(from: ok, request: request)
        #expect(r.text == #"{"answer":2}"# && r.stop_reason == "end_turn" && r.model == "claude-haiku-5-5" && r.usage.output_tokens == 5)

        let failed = Data(#"{"type":"result","is_error":true,"result":"Not logged in","api_error_status":401}"#.utf8)
        #expect(throws: ClaudeError.http(status: 401, body: "Not logged in")) { try CLIProvider.response(from: failed, request: request) }
    }

    /// Spends a little of the real subscription, so it runs only with `FOLIO_LIVE_CLI=1`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FOLIO_LIVE_CLI"] == "1"))
    func liveStructuredAnswer() async throws {
        struct Answer: Decodable { var answer: Int }
        let client = ClaudeClient(provider: CLIProvider(executable: try #require(CLIProvider.find())), overrides: [.classifyFile: TaskConfig(model: TaskConfig.small, effort: .low, maxTokens: 100)])
        let schema: JSONValue = .object(["type": .string("object"), "properties": .object(["answer": .object(["type": .string("integer")])]),
                                         "required": .array([.string("answer")]), "additionalProperties": .bool(false)])
        let r = try await client.structured(.classifyFile, as: Answer.self, schema: schema, system: [.text("Answer briefly.")],
                                            messages: [Message(role: .user, content: [.text("2+3?")])])
        #expect(r.answer == 5)
    }
}
#endif
