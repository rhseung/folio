import FolioDomain
import FolioMarkdown
import FolioStorage
import Foundation

enum NoteTitles {
    static func follow(_ moves: [PlannedMove], _ ctx: ActionContext, move: () throws -> UUID) throws -> UUID? {
        guard moves.contains(where: { NoteFormat(path: $0.from) != nil }) else { return ctx.dryRun ? nil : try move() }
        struct Edit { var store: CourseStore, url: URL, text: String }
        typealias Rename = (note: UUID?, from: String, to: String)
        var renamed: [UUID: [Rename]] = [:]
        var edits: [Edit] = []
        var courses: [(id: UUID, store: CourseStore)] = []

        for store in try ctx.gist.courseStores() {
            let course = try store.load().model.course.id
            courses.append((course, store))
            let file = try ctx.file(course)
            let prefix = ctx.relative(store.url) + "/"
            let byPath = Dictionary(
                moves.filter { $0.from.hasPrefix(prefix) && $0.to.hasPrefix(prefix) }.map {
                    (String($0.from.dropFirst(prefix.count)), String($0.to.dropFirst(prefix.count)))
                },
                uniquingKeysWith: { a, _ in a })
            let entries = Set(file.notes.map(\.path))
            let bare: [Rename] = byPath.filter { from, _ in
                !entries.contains(from) && from.hasPrefix(CourseFolder.notes.rawValue + "/") && NoteFormat(path: from) != nil
            }.map { (note: nil, from: $0.key, to: $0.value) }
            let notes: [Rename] = file.notes.compactMap { e in byPath[e.path].map { (note: e.id, from: e.path, to: $0) } } + bare
            if !notes.isEmpty { renamed[course] = notes }
        }
        guard !renamed.isEmpty else { return ctx.dryRun ? nil : try move() }

        let title = { (path: String) in ((path as NSString).lastPathComponent as NSString).deletingPathExtension }
        let folder = { (path: String) in (path as NSString).deletingLastPathComponent }
        let everywhere = renamed.values.flatMap { $0 }

        for (course, store) in courses {
            let notes = renamed[course] ?? []
            for n in try ctx.notes(course) where !notes.isEmpty || n.format == .markdown {
                let path = store.notePath(of: n.url)
                let own = notes.first { $0.from == path }
                var text = try store.read(n)
                let before = text
                if let own {
                    text = NoteTemplate.retitled(text, from: title(own.from), to: title(own.to), format: n.format)
                    text = NoteTemplate.rebased(text, from: folder(own.from), to: folder(own.to), format: n.format)
                }
                if n.format == .markdown {
                    for r in notes { text = WikiLink.retargeted(text, from: title(r.from), to: title(r.to)) }
                    for r in everywhere {
                        if let id = r.note { text = WikiLink.retitled(text, note: id, from: title(r.from), to: title(r.to)) }
                    }
                }
                if text != before { edits.append(Edit(store: store, url: own.map { store.fileURL($0.to) } ?? n.url, text: text)) }
            }
        }

        let batch = ctx.dryRun ? nil : try move()
        for (course, notes) in renamed where notes.contains(where: { $0.note != nil }) {
            try ctx.edit(course) { f in
                for n in notes { if let i = f.notes.firstIndex(where: { $0.id == n.note }) { f.notes[i].path = n.to } }
            }
        }
        for e in edits {
            try ctx.io(Change(.changed, ctx.relative(e.url))) {
                try e.store.write(NoteFile(url: e.url, meta: NoteMeta(id: nil)), text: e.text)
            }
        }
        return batch
    }
}
