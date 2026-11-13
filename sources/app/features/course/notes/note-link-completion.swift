import FolioActions
import FolioDomain
import FolioIndex
import FolioMarkdown
import FolioStorage
import Foundation
import PDFKit

@MainActor final class NoteLinkCompletion: NoteLinkSource {
    let workspace: Workspace
    let courseId: UUID
    let note: NoteFile
    private var index: SearchStore?
    private var refreshing: Task<Void, Never>?
    private var refreshedAt: Date?
    private var listed: (revision: Int, notes: [UUID: [NoteFile]]) = (-1, [:])

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
        let titles = self.course.map { notes(of: $0).map(\.title) } ?? []
        if LinkCandidates.offersNewNote(name, titles: titles) {
            items.append(CompletionItem(id: Self.newNote, title: String(localized: .notesAssistLinkNew(name)), symbol: "plus", body: name))
        }
        return items
    }

    func item(for found: SearchItem, alias: String?) -> CompletionItem {
        let link = AppLink(found)
        let name = alias ?? found.title
        let elsewhere = found.courseId == courseId ? nil : workspace.course(found.courseId)?.title
        if found.kind == .material, MaterialFormat(path: found.title) == .pdf {
            let body = WikiLink.written(link.kind.rawValue, found.id, fragment: "page=", alias: name)
            let caret = (body as NSString).range(of: "#page=").upperBound
            return CompletionItem(
                id: "link.\(found.id)", title: found.title, detail: elsewhere, symbol: found.kind.symbol, body: body,
                caret: caret, continues: true)
        }
        let body = WikiLink.written(link.kind.rawValue, found.id, alias: name)
        return CompletionItem(
            id: "link.\(found.id)", title: found.title, detail: elsewhere, symbol: found.kind.symbol, body: body, caret: body.utf16.count)
    }

    func headings(of link: LinkQuery, typed: String, text: String) -> [CompletionItem] {
        guard let (target, id, body) = resolve(link.target, text: text) else { return [] }
        let items = ParsedNote(body).headings.filter { WikiLink.linkable(heading: $0.text) }.enumerated().map { i, h in
            let written = WikiLink.written("note", id, fragment: h.text, alias: link.alias ?? target.title)
            return CompletionItem(
                id: "heading.\(i)", title: h.text, detail: String(repeating: "#", count: h.level), symbol: "number",
                body: written, caret: written.utf16.count)
        }
        return Completion.filter(items, typed)
    }

    func blocks(of link: LinkQuery, typed: String, text: String) -> [CompletionItem] {
        guard let (target, id, body) = resolve(link.target, text: text) else { return [] }
        let items = ParsedNote(body).linkableBlocks.map { b in
            // ID 없는 블록은 고를 때(`take`) ID를 받는다. 그때까지 링크는 그 줄을 담고, `take`가 그 줄을 읽는다.
            let written = WikiLink.written("note", id, fragment: "^" + (b.id ?? ""), alias: link.alias ?? target.title)
            return CompletionItem(
                id: b.id.map { "block.\($0)" } ?? "\(Self.newBlock)\(b.line)", title: b.excerpt.isEmpty ? "^" + (b.id ?? "") : b.excerpt,
                detail: b.id.map { "^" + $0 }, symbol: "text.quote", keywords: b.id.map { [$0] } ?? [],
                body: written, caret: written.utf16.count)
        }
        return Completion.filter(items, typed)
    }

    func pages(of link: LinkQuery, typed: String) -> [CompletionItem] {
        guard let target = WikiLink.all(in: "[[\(link.target)]]").first, target.objectKind == "material", let id = target.objectID,
            let holder = workspace.courses.first(where: { $0.file.materials.contains { $0.id == id } }),
            let material = holder.file.materials.first(where: { $0.id == id })
        else { return [] }
        // 뷰어는 마지막 쪽을 0부터 세어 기록한다.
        let last = ((try? holder.store.log.readAll()) ?? []).events(MaterialViewEvent.self).last { $0.event.materialId == id }.map {
            $0.event.page + 1
        }
        let count = PDFDocument(url: holder.store.fileURL(material.path))?.pageCount
        let name = link.alias ?? (material.path as NSString).lastPathComponent
        return LinkCandidates.pages(count: count, last: last, typed: typed).map { n in
            let written = WikiLink.written("material", id, fragment: "page=\(n)", alias: name)
            return CompletionItem(
                id: "page.\(n)", title: String(localized: .notesAssistLinkPage(n)),
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
            let (target, id, body) = resolve(link.target, text: text)
        else { return (item, nil) }
        let blockID = BlockID.make(avoiding: Set(ParsedNote(body).blockIDs))
        let written = WikiLink.written("note", id, fragment: "^" + blockID, alias: link.alias ?? target.title)
        let picked = CompletionItem(id: item.id, title: item.title, body: written, caret: written.utf16.count)
        if target.url.standardizedFileURL == note.url.standardizedFileURL {
            return ParsedNote.blockTag(in: text, line: line, id: blockID).map { (picked, $0) }
        }
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

    func resolve(_ target: String, text: String) -> (note: NoteFile, id: UUID, text: String)? {
        let link = WikiLink.all(in: "[[\(target)]]").first
        let found: NoteFile?
        if let id = link?.noteID {
            found = note.meta.id == id ? note : workspace.courses.lazy.compactMap { self.notes(of: $0).first { $0.meta.id == id } }.first
        } else if link?.objectKind == nil {
            found = course.flatMap { notes(of: $0).titled(target) }
        } else {
            found = nil
        }
        guard let found, found.format == .markdown, let id = found.meta.id else { return nil }
        if found.url.standardizedFileURL == note.url.standardizedFileURL { return (found, id, text) }
        guard let body = try? holder(of: found)?.store.read(found) else { return nil }
        return (found, id, body)
    }

    // 노트 목록은 Notes 폴더를 훑는데, 큰 iCloud 폴더에서는 입력이 멈출 만큼 느리다. 그래서 키마다 읽지 않고
    // `notesRevision`마다 한 번 읽는다. 모든 노트 액션과 폴더 다시 읽기가 이 값을 올린다.
    func notes(of course: LoadedCourse) -> [NoteFile] {
        if listed.revision != workspace.notesRevision { listed = (workspace.notesRevision, [:]) }
        if let cached = listed.notes[course.id] { return cached }
        let found = course.store.notes(in: course.file)
        listed.notes[course.id] = found
        return found
    }

    func holder(of note: NoteFile) -> LoadedCourse? {
        workspace.courses.first { note.url.standardizedFileURL.path.hasPrefix($0.store.url.standardizedFileURL.path + "/") }
    }

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
