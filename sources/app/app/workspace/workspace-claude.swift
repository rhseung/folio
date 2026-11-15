import FolioAI
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

extension Workspace {
    var usesSubscription: Bool {
        #if os(macOS)
        UserDefaults.standard.object(forKey: Self.subscriptionKey) as? Bool ?? true
        #else
        false
        #endif
    }
    static let subscriptionKey = "claude.subscription"

    var claudeReady: Bool {
        _ = claudeRevision
        // 테스트 host나 미리보기는 이 Mac의 Claude에 닿으면 안 된다. 지금은 렉처를 더하면 바로 Claude에 묻는데, 그러면 테스트가
        // 실제 답을 기다리고 비용을 내고 그 답에 기대게 된다. 테스트는 가짜 프로바이더를 준다.
        guard !LocalFolders.isIsolated() else { return false }
        #if os(macOS)
        if usesSubscription { return CLIProvider.find() != nil }
        #endif
        return !(APIKeyStore.read() ?? "").isEmpty
    }

    func claude(for course: LoadedCourse, folioTools: Bool = false) -> ClaudeClient {
        #if os(macOS)
        if usesSubscription, let executable = CLIProvider.find() {
            let tools =
                folioTools
                ? CLIProvider.findFolio().flatMap { folio in gist.map { CLIProvider.FolioTools(executable: folio, gist: $0.url) } } : nil
            // 구독으로 처리하는 호출이므로 API 사용량과 비용 기록에 넣지 않는다.
            return ClaudeClient(provider: CLIProvider(executable: executable, workingDirectory: course.store.url, folio: tools))
        }
        #endif
        let log = course.store.log, device = device
        return ClaudeClient(provider: APIProvider(apiKey: { APIKeyStore.read() })) { event in
            try? log.append(event, device: device, at: .now)
        }
    }

    func action(_ proposal: ActionProposal) -> (any Action)? {
        guard let type = Actions.all.first(where: { $0.command == proposal.command }) else { return nil }
        return try? Self.decode(type, proposal.input)
    }

    private static func decode<A: Action>(_ type: A.Type, _ input: JSONValue) throws -> A {
        try JSONDecoder.folio.decode(A.self, from: JSONEncoder().encode(input))
    }

    func monthlyAPIUsage() -> [MonthlyUsage] {
        let events = courses.flatMap { course in
            ((try? course.store.log.readAll()) ?? []).events(APIUsageEvent.self)
        }
        return APIUsageEvent.monthly(events, calendar: calendar)
    }
}
