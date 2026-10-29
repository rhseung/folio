import FolioActions
import FolioAI
import FolioDomain
import FolioMarkdown
import FolioStorage
import Foundation

/// The Claude panel's reads and writes: chats, context items, notes made from answers, and API usage.
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

    func chats(_ course: LoadedCourse) -> [StoredDocument<Chat>] {
        (try? course.store.chats()) ?? []
    }

    func save(_ chat: StoredDocument<Chat>, course: LoadedCourse) {
        // folio:not-an-action chat history is not an action
        perform { try course.store.save(chat) }
    }

    /// A client whose usage events go to this device's log in the course folder.
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

    func notes(_ course: LoadedCourse) -> [NoteFile] {
        ((try? course.store.notes()) ?? []).filter { $0.meta.id != nil }
    }

    /// The note's saved body (without frontmatter) as a context item.
    func noteContext(_ id: UUID, course: LoadedCourse, open: Bool) -> ContextItem? {
        guard let note = try? course.store.note(id: id), let text = try? course.store.read(note) else { return nil }
        let body = Frontmatter.split(text).body
        let images = course.store.contextImages(of: note, body: body).map { ContextItem.Image(name: $0.name, data: $0.data) }
        return ContextBuilder.note(id: id, title: note.title, body: body, images: images, open: open)
    }

    func materialContext(_ material: Material, course: LoadedCourse) -> ContextItem? {
        do {
            guard let text = try course.store.contextText(ofMaterial: material.path), !text.isEmpty else {
                error = "이 파일에서는 글자를 읽을 수 없습니다."
                return nil
            }
            return ContextBuilder.material(path: material.path, text: text)
        } catch {
            self.error = "\(error)"
            return nil
        }
    }

    /// Sessions let go of the note first: a note left behind by a failed trash is harmless, a link to nothing is not.
    func deleteNote(_ note: NoteFile, course: LoadedCourse) {
        guard let path = course.store.coursePath(of: note.url) else { return }
        run(NoteRemove(course: course.id, note: path))
    }

    /// A free note holding `text`, for an answer saved while no note is open.
    func createNote(title: String, body: String, course: LoadedCourse) -> UUID? {
        run(NoteAdd(course: course.id, title: title, body: body))?.made
    }

    /// API use per month across every course's logs, newest first, for the settings page.
    func monthlyAPIUsage() -> [MonthlyUsage] {
        let events = courses.flatMap { course in
            ((try? course.store.log.readAll()) ?? []).events(APIUsageEvent.self)
        }
        return APIUsageEvent.monthly(events, calendar: calendar)
    }
}
