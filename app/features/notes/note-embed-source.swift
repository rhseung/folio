import FolioActions
import FolioDomain
import FolioMarkdown
import FolioStorage
import Foundation
import Observation
import UniformTypeIdentifiers

// 키를 누를 때마다 미리보기가 다시 그리므로, 노트는 그때마다가 아니라 `revision`(workspace의 `notesRevision`)마다 한 번
// 읽는다.
final class NoteEmbedSource {
    private let store: CourseStore
    private let others: [CourseStore]
    private let own: URL?
    private var revision: Int?
    private var notes: [NoteFile]?
    private var elsewhere: [NoteFile]?
    private var texts: [URL: String] = [:]
    private var current: String?

    let name: (AppLink) -> String?

    init(store: CourseStore, others: [CourseStore] = [], own: URL?, name: @escaping (AppLink) -> String? = { _ in nil }) {
        self.store = store
        self.others = others
        self.own = own
        self.name = name
    }

    @MainActor convenience init(workspace: Workspace, course: LoadedCourse, own: URL?) {
        self.init(store: course.store, others: workspace.courses.filter { $0.id != course.id }.map(\.store), own: own) {
            [weak workspace] link in
            MainActor.assumeIsolated { workspace?.name(of: link) }
        }
    }

    func embeds(revision: Int, text: String) -> NoteEmbeds {
        current = text
        if revision != self.revision {
            self.revision = revision
            notes = nil
            elsewhere = nil
            texts = [:]
        }

        let labels = NoteEmbeds.Labels(
            missing: String(localized: .notesEmbedMissing), loop: String(localized: .notesEmbedLoop),
            tooDeep: String(localized: .notesEmbedTooDeep))
        return NoteEmbeds(
            key: own?.standardizedFileURL.path, labels: labels, title: { [self] id in noteFile(id: id)?.title },
            hasNote: { [self] title in note(titled: title) != nil },
            name: { [name] href in AppLink(string: href).flatMap { link in name(link).map(link.label) } }
        ) { [self] link in find(link) }
    }

    private func note(titled title: String) -> NoteFile? {
        if notes == nil { notes = (try? store.notes()) ?? [] }
        return notes?.linked(title)
    }

    private func noteFile(id: UUID) -> NoteFile? {
        if notes == nil { notes = (try? store.notes()) ?? [] }
        if let found = notes?.first(where: { $0.meta.id == id }) { return found }
        if elsewhere == nil { elsewhere = others.flatMap { (try? $0.notes()) ?? [] } }
        return elsewhere?.first { $0.meta.id == id }
    }

    private func find(_ link: WikiLink) -> NoteEmbeds.Note? {
        let named: NoteFile? = if let id = link.noteID { noteFile(id: id) } else { note(titled: link.target) }
        guard let note = named, note.format == .markdown else { return nil }
        if note.url.standardizedFileURL == own?.standardizedFileURL, let current {
            return NoteEmbeds.Note(key: note.url.standardizedFileURL.path, text: current, math: note.meta.math.rawValue)
        }
        guard let text = texts[note.url] ?? (try? store.read(note)) else { return nil }
        texts[note.url] = text
        return NoteEmbeds.Note(key: note.url.standardizedFileURL.path, text: text, math: note.meta.math.rawValue)
    }
}
