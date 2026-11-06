import FolioActions
import FolioDomain
import FolioIndex
import FolioMarkdown
import FolioStorage
import Foundation
import Testing
@testable import Folio

/// Link completion's candidates from the fixture folder, and what taking one writes (#31).
@MainActor
struct NoteLinkCompletionTests {
    let workspace: Workspace
    let own: NoteFile
    let other: UUID
    let links: NoteLinkCompletion

    static let otherText = """
    # 매칭

    증가 경로가 없으면 최대다. ^max

    ## 쾨니그 정리

    이분 그래프에서 최대 매칭과 최소 덮개는 크기가 같다.
    """

    init() throws {
        workspace = try fixtureWorkspace()
        // The fixture's files aren't tracked until asked.
        workspace.run(MaterialTrack(course: graphTheory))
        other = try #require(workspace.run(NoteAdd(course: graphTheory, title: "매칭 정리", body: Self.otherText))?.made)
        let ownID = try #require(workspace.run(NoteAdd(course: graphTheory, title: "지금 노트", body: "# 지금\n"))?.made)
        let course = try #require(workspace.course(graphTheory))
        own = try #require(try course.store.note(id: ownID))
        let index = try SearchStore(url: nil)
        try index.refresh(try #require(workspace.gist))
        links = NoteLinkCompletion(workspace: workspace, course: graphTheory, note: own, index: index)
    }

    func query(_ marked: String) throws -> CompletionQuery {
        let caret = (marked as NSString).range(of: "|").location
        let text = (marked as NSString).replacingCharacters(in: NSRange(location: caret, length: 1), with: "")
        return try #require(Completion.query(in: text as NSString, caret: caret, catalog: CompletionCatalog()))
    }

    @Test func notesAndOtherThingsGoInByID() async throws {
        let items = await links.candidates(for: try query("[[매칭|]]"), text: "")
        let note = try #require(items.first { $0.title == "매칭 정리" })
        #expect(note.body == "[[note:\(other.uuidString)|매칭 정리]]" && note.symbol == "doc.text")
        // The note being written isn't offered, and a PDF's link goes on to its page.
        #expect(!items.contains { $0.title == "지금 노트" })
        let pdf = try #require(await links.candidates(for: try query("[[Matchings|]]"), text: "").first { $0.title == "05_Matchings.pdf" })
        #expect(pdf.continues && pdf.body.hasPrefix("[[material:") && pdf.body.hasSuffix("#page=|05_Matchings.pdf]]"))
        #expect((pdf.body as NSString).substring(to: pdf.caret ?? 0).hasSuffix("#page="))
        // Nothing typed: this course's notes.
        let start = await links.candidates(for: try query("[[|]]"), text: "")
        #expect(start.contains { $0.title == "매칭 정리" } && start.allSatisfy { $0.symbol == "doc.text" })
    }

    @Test func examsAreFoundToo() async throws {
        let exam = try #require(workspace.run(ExamAdd(course: graphTheory, title: "기말고사"))?.made)
        let index = try SearchStore(url: nil)
        try index.refresh(try #require(workspace.gist))
        let fresh = NoteLinkCompletion(workspace: workspace, course: graphTheory, note: own, index: index)
        let items = await fresh.candidates(for: try query("[[기말|]]"), text: "")
        #expect(items.first?.body == "[[exam:\(exam.uuidString)|기말고사]]")
    }

    @Test func aNameNoNoteHasMakesOne() async throws {
        let q = try query("[[새로운 주제|]]")
        let items = await links.candidates(for: q, text: "")
        let make = try #require(items.last)
        #expect(make.id == NoteLinkCompletion.newNote)
        let taken = try #require(links.take(make, for: q, text: ""))
        let made = try #require(try workspace.course(graphTheory)?.store.notes().titled("새로운 주제")?.meta.id)
        #expect(taken.item.body == "[[note:\(made.uuidString)|새로운 주제]]" && taken.own == nil)
        #expect(!(await links.candidates(for: try query("[[매칭 정리|]]"), text: "")).contains { $0.id == NoteLinkCompletion.newNote })
    }

    @Test func headingsOfTheNoteNamed() async throws {
        let items = await links.candidates(for: try query("[[매칭 정리#쾨|]]"), text: "")
        #expect(items.map(\.title) == ["쾨니그 정리"])
        #expect(items.first?.body == "[[note:\(other.uuidString)#쾨니그 정리|매칭 정리]]")
        // By ID, keeping the name already written.
        let byID = await links.candidates(for: try query("[[note:\(other.uuidString)#||내 이름]]"), text: "")
        #expect(byID.map(\.body) == ["[[note:\(other.uuidString)#매칭|내 이름]]", "[[note:\(other.uuidString)#쾨니그 정리|내 이름]]"])
    }

    @Test func aBlockWithoutAnIDGetsOneInItsNote() async throws {
        let q = try query("[[매칭 정리#^|]]")
        let items = await links.candidates(for: q, text: "")
        #expect(items.map(\.title) == ["증가 경로가 없으면 최대다.", "이분 그래프에서 최대 매칭과 최소 덮개는 크기가 같다."])
        #expect(items[0].body == "[[note:\(other.uuidString)#^max|매칭 정리]]")
        let revision = workspace.notesRevision
        let taken = try #require(links.take(items[1], for: q, text: ""))
        let course = try #require(workspace.course(graphTheory))
        let written = try course.store.read(try #require(try course.store.note(id: other)))
        let id = try #require(ParsedNote(written).blockIDs.last)
        #expect(written.contains("이분 그래프에서 최대 매칭과 최소 덮개는 크기가 같다. ^\(id)"))
        #expect(taken.item.body == "[[note:\(other.uuidString)#^\(id)|매칭 정리]]" && taken.own == nil)
        #expect(workspace.notesRevision > revision)
    }

    /// The note being written gets the ID in the editor, which saves it with everything else typed.
    @Test func aBlockOfThisNoteGetsItsIDInTheEditor() async throws {
        let text = "# 지금\n\n앞 문단\n\n[[지금 노트#^]]"
        let q = try query("# 지금\n\n앞 문단\n\n[[지금 노트#^|]]")
        let items = await links.candidates(for: q, text: text)
        let block = try #require(items.first { $0.title == "앞 문단" })
        let taken = try #require(links.take(block, for: q, text: text))
        let own = try #require(taken.own)
        let id = String(try #require(taken.item.body.firstMatch(of: /#\^([a-z0-9]+)\|/)?.1))
        #expect(own.applied(to: text as NSString) == "# 지금\n\n앞 문단 ^\(id)\n\n[[지금 노트#^]]")
    }

    @Test func pagesOfAFileStartAtTheLastOneSeen() async throws {
        let course = try #require(workspace.course(graphTheory))
        let material = try #require(course.file.materials.first { $0.path.hasSuffix("05_Matchings.pdf") })
        try course.store.log.append(MaterialViewEvent(materialId: material.id, page: 6), device: workspace.device, at: .now)
        let items = await links.candidates(for: try query("[[material:\(material.id.uuidString)#page=|]]"), text: "")
        // The fixture's PDF is a placeholder with no pages to count, so the last page seen is all there is.
        #expect(items.first?.body == "[[material:\(material.id.uuidString)#page=7|05_Matchings.pdf]]")
        #expect(items.first?.detail == String(localized: .notesAssistLinkLastPage))
    }
}
