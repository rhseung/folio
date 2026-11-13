import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Testing

@testable import FolioCLI

/// `folio link` and `folio open` name their target the way every other command does and print its `folio://` link.
struct LinkCommandTests {
    let h = Harness()

    @Test func linksACourseAndItsItems() throws {
        let gist = try Harness.fixtureCopy()
        #expect(h.cli(["exam", "add", "EC4207", "중간고사", "--start", "2026-10-22 10:00"], gist: gist).code == 0)
        let course = h.cli(["link", "course", "EC4207"], gist: gist)
        #expect(course.code == 0, "\(course.err)")
        #expect(course.out == AppLink.course(Harness.graphTheory).string)
        #expect(h.cli(["link", "course", "EC4207", "--section", "materials"], gist: gist).out.hasSuffix("/materials"))

        let exam = h.cli(["link", "exam", "EC4207/중간고사", "--json"], gist: gist)
        let json = try #require(try JSONSerialization.jsonObject(with: Data(exam.out.utf8)) as? [String: Any])
        let text = try #require(json["link"] as? String)
        let link = try #require(AppLink(string: text))
        let id = try #require(link.id)
        let file = try GISTStore(url: gist).courseStores().first { (try? $0.load().model.course.id) == Harness.graphTheory }
        #expect(try file?.load().model.exams.first { $0.id == id }?.title == "중간고사")
        #expect(json["title"] as? String == "EC4207/중간고사")
    }

    @Test func aNoteLinkCarriesItsHeadingAndAMaterialItsPage() throws {
        let gist = try Harness.fixtureCopy()
        #expect(h.cli(["note", "add", "EC4207", "매칭 정리", "--kind", "topic"], gist: gist).code == 0)
        let note = h.cli(["link", "note", "EC4207/매칭 정리", "--heading", "정의 (1)"], gist: gist)
        #expect(note.code == 0, "\(note.err)")
        #expect(AppLink(string: note.out)?.anchor == .heading("정의 (1)"))

        #expect(h.cli(["material", "track", "EC4207"], gist: gist).code == 0)
        let material = h.cli(["link", "material", "EC4207/05_Matchings.pdf", "--page", "12"], gist: gist)
        #expect(material.code == 0, "\(material.err)")
        #expect(AppLink(string: material.out)?.anchor == .page(12))
    }

    /// Each kind is looked up as itself: a kind the lookup forgot fell through to the notes and printed a note's ID.
    @Test func eachKindLinksAsItself() throws {
        let gist = try Harness.fixtureCopy()
        #expect(h.cli(["exam", "add", "EC4207", "중간고사"], gist: gist).code == 0)
        #expect(h.cli(["note", "add", "EC4207", "매칭 정리", "--kind", "topic"], gist: gist).code == 0)
        #expect(h.cli(["material", "track", "EC4207"], gist: gist).code == 0)
        let refs: [(AppLink.Kind, String)] = [
            (.course, "EC4207"), (.exam, "EC4207/중간고사"), (.note, "EC4207/매칭 정리"),
            (.material, "EC4207/05_Matchings.pdf"), (.grades, ""),
        ]
        for (kind, ref) in refs {
            let r = h.cli(["link", kind.rawValue] + (ref.isEmpty ? [] : [ref]), gist: gist)
            #expect(r.code == 0, "\(kind): \(r.err)")
            #expect(AppLink(string: r.out)?.kind == kind, "\(kind): \(r.out)")
        }
        #expect(h.cli(["link", "exam", "EC4207/매칭 정리"], gist: gist).code == Exit.notFound.rawValue)
        #expect(h.cli(["link", "material", "EC4207/05_Matchings.pdf", "--heading", "정의"], gist: gist).code == Exit.usage.rawValue)
        #expect(h.cli(["link", "note", "EC4207/매칭 정리", "--page", "2"], gist: gist).code == Exit.usage.rawValue)
    }

    /// A recording is named by its class, as its file is, and its link carries a moment written as the player shows it.
    @Test func aRecordingLinkCarriesItsMoment() throws {
        let gist = try Harness.fixtureCopy()
        #expect(h.cli(["session", "add", "EC4207", "--date", "2026-10-20 10:30"], gist: gist).code == 0)
        let ctx = ActionContext(gist: GISTStore(url: gist), device: h.device, now: h.now)
        let session = try #require(try ctx.file(Harness.graphTheory).sessions.first)
        let name = try ctx.file(Harness.graphTheory).recordingName(of: session, calendar: ctx.calendar)
        let recording = Recording(device: h.device, at: h.now, sessionId: session.id, file: "Recordings/\(name).m4a", duration: 3000)
        try ctx.edit(Harness.graphTheory) { $0.recordings = [recording] }

        let r = h.cli(["link", "recording", "EC4207/10-20", "--time", "12:30"], gist: gist)
        #expect(r.code == 0, "\(r.err)")
        #expect(r.out == AppLink(.recording, recording.id, anchor: .time(750)).string)
        #expect(r.out.hasSuffix("#t=12:30"))
        #expect(h.cli(["link", "recording", "EC4207/\(name).m4a", "--time", "750"], gist: gist).out == r.out)
        #expect(h.cli(["link", "recording", "EC4207/\(name)", "--time", "soon"], gist: gist).code == Exit.usage.rawValue)
        #expect(h.cli(["link", "note", "EC4207/\(name)", "--time", "1:00"], gist: gist).code == Exit.usage.rawValue)
    }

    @Test func placesTakeNoItemAndAnchorsBelongToTheirKind() {
        let gist = try! Harness.fixtureCopy()
        #expect(h.cli(["link", "today"], gist: gist).out == "folio://today")
        #expect(h.cli(["link", "today", "EC4207"], gist: gist).code == Exit.usage.rawValue)
        #expect(h.cli(["link", "course", "EC4207", "--page", "3"], gist: gist).code == Exit.usage.rawValue)
        #expect(h.cli(["link", "settings", "--section", "claude"], gist: gist).out == "folio://settings/claude")
        #expect(h.cli(["link", "settings", "--section", "materials"], gist: gist).code == Exit.usage.rawValue)
        #expect(h.cli(["link", "course", "EC4207", "--section", "claude"], gist: gist).code == Exit.usage.rawValue)
        #expect(h.cli(["link", "grades", "--section", "claude"], gist: gist).code == Exit.usage.rawValue)
        #expect(h.cli(["link", "card", "not-an-id"], gist: gist).code == Exit.usage.rawValue)
        #expect(h.cli(["link", "card", UUID().uuidString], gist: gist).code == Exit.notFound.rawValue)
    }

    @Test func openPrintsTheLinkItWouldOpen() throws {
        let gist = try Harness.fixtureCopy()
        let r = h.cli(["open", "course", "EC4207", "--dry-run"], gist: gist)
        #expect(r.code == 0, "\(r.err)")
        #expect(r.out == AppLink.course(Harness.graphTheory).string)
    }

    @Test func linkIsAnMCPReadToolAndOpenIsNot() {
        let names = Set(MCPServer.readTools().map(\.command))
        #expect(names.contains("link"))
        #expect(!names.contains("open"))
    }
}
