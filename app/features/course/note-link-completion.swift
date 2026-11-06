import FolioActions
import FolioDomain
import FolioIndex
import FolioMarkdown
import FolioStorage
import Foundation
import PDFKit

/// Link completion for one note's edit view (#31): what `[[`, `#`, `#^` and `#page=` offer, from the search index for
/// targets and from the files for headings, blocks and pages. Links go in by ID (#35). What shows in which order is
/// `LinkCandidates`'s; how the link reads, FolioMarkdown's.
@MainActor final class NoteLinkCompletion: NoteLinkSource {
    let workspace: Workspace
    let courseId: UUID
    let note: NoteFile
    private var index: SearchStore?
    private var refreshing: Task<Void, Never>?
    private var refreshedAt: Date?

    /// `index` stands in for this device's index, read up to date already; tests give one in memory.
    init(workspace: Workspace, course: UUID, note: NoteFile, index: SearchStore? = nil) {
        self.workspace = workspace
        courseId = course
        self.note = note
        self.index = index
        if index != nil { refreshedAt = .now }
    }

    var course: LoadedCourse? { workspace.course(courseId) }

    // MARK: Candidates

    func candidates(for query: CompletionQuery, text: String) async -> [CompletionItem] {
        guard case .link(let link) = query.kind else { return [] }
        switch link.part {
        case .target: return await targets(query.text, alias: link.alias)
        case .heading: return headings(of: link, typed: query.text, text: text)
        case .block: return blocks(of: link, typed: query.text, text: text)
        case .page: return pages(of: link, typed: query.text)
        }
    }

    /// What the search index finds for what's typed, this course's first; nothing typed, this course's notes.
    func targets(_ typed: String, alias: String?) async -> [CompletionItem] {
        guard let index = openIndex() else { return [] }
        let course = courseId
        let name = typed.trimmingCharacters(in: .whitespaces)
        let hits = await Task.detached {
            name.isEmpty
                ? ((try? index.items(courses: [course], kinds: [.note])) ?? []).map { SearchHit(item: $0) }
                : (try? index.search(name, limit: 40)) ?? []
        }.value
        guard !Task.isCancelled else { return [] }
        var items = LinkCandidates.order(hits, course: courseId, excluding: note.meta.id).map { item(for: $0.item, alias: alias) }
        let titles = (try? self.course?.store.notes())?.map(\.title) ?? []
        if LinkCandidates.offersNewNote(name, titles: titles) {
            items.append(CompletionItem(id: Self.newNote, title: String(localized: .notesAssistLinkNew(name)), symbol: "plus", body: name))
        }
        return items
    }

    func item(for found: SearchItem, alias: String?) -> CompletionItem {
        let link = AppLink(found)
        let name = alias ?? found.title
        let elsewhere = found.courseId == courseId ? nil : workspace.course(found.courseId)?.title
        // A PDF's link goes on to its page, which the menu that opens there picks.
        if found.kind == .material, found.title.lowercased().hasSuffix(".pdf") {
            let body = WikiLink.written(link.kind.rawValue, found.id, fragment: "page=", alias: name)
            let caret = (body as NSString).range(of: "#page=").upperBound
            return CompletionItem(id: "link.\(found.id)", title: found.title, detail: elsewhere, symbol: found.kind.symbol, body: body,
                                  caret: caret, continues: true)
        }
        let body = WikiLink.written(link.kind.rawValue, found.id, alias: name)
        return CompletionItem(id: "link.\(found.id)", title: found.title, detail: elsewhere, symbol: found.kind.symbol, body: body, caret: body.utf16.count)
    }

    func headings(of link: LinkQuery, typed: String, text: String) -> [CompletionItem] {
        guard let (target, id, body) = resolve(link.target, text: text) else { return [] }
        let items = ParsedNote(body).headings.filter { WikiLink.linkable(heading: $0.text) }.enumerated().map { i, h in
            let written = WikiLink.written("note", id, fragment: h.text, alias: link.alias ?? target.title)
            return CompletionItem(id: "heading.\(i)", title: h.text, detail: String(repeating: "#", count: h.level), symbol: "number",
                                  body: written, caret: written.utf16.count)
        }
        return Completion.filter(items, typed)
    }

    func blocks(of link: LinkQuery, typed: String, text: String) -> [CompletionItem] {
        guard let (target, id, body) = resolve(link.target, text: text) else { return [] }
        let items = ParsedNote(body).linkableBlocks.map { b in
            // A block without an ID gets one when picked (`take`); until then the link holds the line, which `take` reads.
            let written = WikiLink.written("note", id, fragment: "^" + (b.id ?? ""), alias: link.alias ?? target.title)
            return CompletionItem(id: b.id.map { "block.\($0)" } ?? "\(Self.newBlock)\(b.line)", title: b.excerpt.isEmpty ? "^" + (b.id ?? "") : b.excerpt,
                                  detail: b.id.map { "^" + $0 }, symbol: "text.quote", keywords: b.id.map { [$0] } ?? [],
                                  body: written, caret: written.utf16.count)
        }
        return Completion.filter(items, typed)
    }

    func pages(of link: LinkQuery, typed: String) -> [CompletionItem] {
        guard let target = WikiLink.all(in: "[[\(link.target)]]").first, target.objectKind == "material", let id = target.objectID,
              let holder = workspace.courses.first(where: { $0.file.materials.contains { $0.id == id } }),
              let material = holder.file.materials.first(where: { $0.id == id }) else { return [] }
        // The viewer logs the page it was left at, 0-based.
        let last = ((try? holder.store.log.readAll()) ?? []).events(MaterialViewEvent.self).last { $0.event.materialId == id }.map { $0.event.page + 1 }
        // A file iCloud hasn't downloaded has no page count; its last page and the number typed still go.
        let count = PDFDocument(url: holder.store.fileURL(material.path))?.pageCount
        let name = link.alias ?? (material.path as NSString).lastPathComponent
        return LinkCandidates.pages(count: count, last: last, typed: typed).map { n in
            let written = WikiLink.written("material", id, fragment: "page=\(n)", alias: name)
            return CompletionItem(id: "page.\(n)", title: String(localized: .notesAssistLinkPage(n)),
                                  detail: n == last ? String(localized: .notesAssistLinkLastPage) : nil, symbol: "doc",
                                  body: written, caret: written.utf16.count)
        }
    }

    // MARK: Taking one

    func take(_ item: CompletionItem, for query: CompletionQuery, text: String) -> (item: CompletionItem, own: SourceEditing.Edit?)? {
        guard case .link(let link) = query.kind else { return (item, nil) }
        if item.id == Self.newNote {
            guard let made = workspace.run(NoteAdd(course: courseId, title: item.body))?.made else { return nil }
            let written = WikiLink.written("note", made, alias: link.alias ?? item.body)
            return (CompletionItem(id: item.id, title: item.title, body: written, caret: written.utf16.count), nil)
        }
        guard item.id.hasPrefix(Self.newBlock), let line = Int(item.id.dropFirst(Self.newBlock.count)),
              let (target, id, body) = resolve(link.target, text: text) else { return (item, nil) }
        let blockID = BlockID.make(avoiding: Set(ParsedNote(body).blockIDs))
        let written = WikiLink.written("note", id, fragment: "^" + blockID, alias: link.alias ?? target.title)
        let picked = CompletionItem(id: item.id, title: item.title, body: written, caret: written.utf16.count)
        if target.url.standardizedFileURL == note.url.standardizedFileURL {
            return ParsedNote.blockTag(in: text, line: line, id: blockID).map { (picked, $0) }
        }
        // Another note's file gets the ID, through the action every note write goes through, refused if the file
        // changed since it was read here.
        guard let holder = holder(of: target), let tag = ParsedNote.blockTag(in: body, line: line, id: blockID) else { return nil }
        let path = holder.store.notePath(of: target.url)
        do {
            try workspace.runThrowing(NoteWrite(course: holder.id, note: path, text: tag.applied(to: body as NSString), expected: body))
        } catch {
            workspace.error = "\(error)"
            return nil
        }
        return (picked, nil)
    }

    // MARK: Finding

    static let newNote = "link.new"
    static let newBlock = "block.new."

    /// The note a link names, its ID, and its text: by ID in any course, this course's first, or by title in this
    /// course. The note being written is read from the editor, which may be ahead of its file.
    func resolve(_ target: String, text: String) -> (note: NoteFile, id: UUID, text: String)? {
        let link = WikiLink.all(in: "[[\(target)]]").first
        let found: NoteFile?
        if let id = link?.noteID {
            found = note.meta.id == id ? note : workspace.courses.lazy.compactMap { try? $0.store.note(id: id) }.first
        } else if link?.objectKind == nil {
            found = (try? course?.store.notes())?.titled(target)
        } else {
            found = nil
        }
        guard let found, found.format == .markdown, let id = found.meta.id else { return nil }
        if found.url.standardizedFileURL == note.url.standardizedFileURL { return (found, id, text) }
        guard let body = try? holder(of: found)?.store.read(found) else { return nil }
        return (found, id, body)
    }

    func holder(of note: NoteFile) -> LoadedCourse? {
        workspace.courses.first { note.url.standardizedFileURL.path.hasPrefix($0.store.url.standardizedFileURL.path + "/") }
    }

    /// The index answers at once with what it has; courses changed since it was last read are read again behind it,
    /// at most every few seconds, so a note made a moment ago shows up from the next key on.
    func openIndex() -> SearchStore? {
        guard let gist = workspace.gist else { return nil }
        if index == nil { index = try? SearchStore.local(for: gist) }
        if let index, refreshing == nil, refreshedAt.map({ Date.now.timeIntervalSince($0) > 5 }) ?? true {
            refreshing = Task { [weak self] in
                await Task.detached { _ = try? index.refresh(gist) }.value
                self?.refreshing = nil
                self?.refreshedAt = .now
            }
        }
        return index
    }
}
