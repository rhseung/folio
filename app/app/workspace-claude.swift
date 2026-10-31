import FolioActions
import FolioAI
import FolioDomain
import FolioStorage
import Foundation

extension Workspace {
    /// The Mac answers through the user's Claude Code subscription unless settings pick the API key; the iPad can't run it.
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
        #if os(macOS)
        if usesSubscription { return CLIProvider.find() != nil }
        #endif
        return !(APIKeyStore.read() ?? "").isEmpty
    }

    /// `folioTools` gives the chat Folio's actions as proposals; only the subscription's CLI can run the `folio` server.
    func claude(for course: LoadedCourse, folioTools: Bool = false) -> ClaudeClient {
        #if os(macOS)
        if usesSubscription, let executable = CLIProvider.find() {
            let tools = folioTools ? CLIProvider.findFolio().flatMap { folio in gist.map { CLIProvider.FolioTools(executable: folio, gist: $0.url) } } : nil
            // Covered by the subscription, so these calls stay out of the API usage and cost log.
            return ClaudeClient(provider: CLIProvider(executable: executable, workingDirectory: course.store.url, folio: tools))
        }
        #endif
        let log = course.store.log, device = device
        return ClaudeClient(provider: APIProvider(apiKey: { APIKeyStore.read() })) { event in
            try? log.append(event, device: device, at: .now)
        }
    }

    /// The action a chat proposal stands for. Its input already holds UUIDs, so no name lookup is needed.
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
