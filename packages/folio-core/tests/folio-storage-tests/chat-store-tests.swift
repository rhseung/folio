import FolioDomain
import FolioFixtures
import FolioStorage
import Foundation
import Testing

struct ChatStoreTests {
    @Test func chatsRoundTripNewestFirstAndKeepUnknownKeys() throws {
        let gist = GISTStore(url: try Fixture.standard.copyToTemp())
        let store = try #require(try gist.courseStores().first)
        #expect(try store.chats().isEmpty)

        let device = UUID(), t0 = Date(timeIntervalSince1970: 1_800_000_000)
        var old = Chat(device: device, at: t0, title: "행렬식")
        old.messages = [ChatMessage(role: .user, text: "질문", at: t0, context: ["과목 요약"]), ChatMessage(role: .assistant, text: "$x$", at: t0)]
        let new = Chat(device: device, at: t0.addingTimeInterval(60), title: "고유값")
        try store.save(StoredDocument(new: old))
        try store.save(StoredDocument(new: new))

        let chats = try store.chats()
        #expect(chats.map(\.model.title) == ["고유값", "행렬식"])
        #expect(chats[1].model == old)

        // A newer app version's field survives a save from this version.
        let url = store.url.appending(path: ".folio/chats/\(old.id.uuidString).json")
        var raw = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect(raw["schemaVersion"] as? Int == 1)
        raw["pinned"] = true
        try JSONSerialization.data(withJSONObject: raw).write(to: url)
        var doc = try #require(try store.chats().first { $0.model.id == old.id })
        doc.model.title = "행렬식 2"
        try store.save(doc)
        let again = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect(again["pinned"] as? Bool == true && again["title"] as? String == "행렬식 2")
    }

    @Test func materialTextForContext() throws {
        let gist = GISTStore(url: try Fixture.standard.copyToTemp())
        let store = try #require(try gist.courseStores().first)
        try Data("\\section{Trees}".utf8).write(to: store.url.appending(path: "Notes/x.tex"))
        #expect(try store.contextText(ofMaterial: "Notes/x.tex") == "\\section{Trees}")
        try Data([0, 1]).write(to: store.url.appending(path: "Notes/x.bin"))
        #expect(try store.contextText(ofMaterial: "Notes/x.bin") == nil)
    }
}
