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

    func claude(for course: LoadedCourse) -> ClaudeClient {
        #if os(macOS)
        if usesSubscription, let executable = CLIProvider.find() {
            // Covered by the subscription, so these calls stay out of the API usage and cost log.
            return ClaudeClient(provider: CLIProvider(executable: executable, workingDirectory: course.store.url))
        }
        #endif
        let log = course.store.log, device = device
        return ClaudeClient(provider: APIProvider(apiKey: { APIKeyStore.read() })) { event in
            try? log.append(event, device: device, at: .now)
        }
    }

    /// Sessions let go of the note first: a note left behind by a failed trash is harmless, a link to nothing is not.
    func deleteNote(_ note: NoteFile, course: LoadedCourse) {
        guard let path = course.store.coursePath(of: note.url) else { return }
        run(NoteRemove(course: course.id, note: path))
    }

    func monthlyAPIUsage() -> [MonthlyUsage] {
        let events = courses.flatMap { course in
            ((try? course.store.log.readAll()) ?? []).events(APIUsageEvent.self)
        }
        return APIUsageEvent.monthly(events, calendar: calendar)
    }
}
