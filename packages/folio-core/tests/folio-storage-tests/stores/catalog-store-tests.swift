import FolioDomain
import FolioFixtures
@testable import FolioStorage
import Foundation
import Testing

struct CatalogStoreTests {
    @Test func savingRequirementsKeepsUnknownKeys() throws {
        let gist = GISTStore(url: try Fixture.standard.copyToTemp())
        let category = Category(device: UUID(), at: Date(timeIntervalSince1970: 0), name: "전공필수", group: "전공", minCredits: 18)
        try gist.save(StoredDocument(new: Catalog(categories: [category])))

        // Fields a newer app version might have written.
        var raw = try JSONFormat.decoder.decode(JSONValue.self, from: Data(contentsOf: gist.catalogURL))
        raw["futureTopLevel"] = .string("keep")
        guard case .array(var items)? = raw["categories"] else { Issue.record("no categories"); return }
        items[0]["futureCategoryField"] = .number(7)
        raw["categories"] = .array(items)
        try JSONFormat.encoder.encode(raw).write(to: gist.catalogURL)

        var doc = try gist.loadCatalog()
        doc.model.categories[0].minCredits = 21
        doc.model.categories[0].maxCredits = 30
        try gist.save(doc)

        let reloaded = try gist.loadCatalog().model.categories[0]
        #expect(reloaded.minCredits == 21)
        #expect(reloaded.maxCredits == 30)
        #expect(reloaded.group == "전공")
        let saved = try JSONFormat.decoder.decode(JSONValue.self, from: Data(contentsOf: gist.catalogURL))
        #expect(saved["futureTopLevel"] == .string("keep"))
        guard case .array(let savedItems)? = saved["categories"] else { Issue.record("no categories"); return }
        #expect(savedItems[0]["futureCategoryField"] == .number(7))
    }
}
