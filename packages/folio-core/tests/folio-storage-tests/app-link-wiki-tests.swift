import FolioDomain
import FolioMarkdown
import Foundation
import Testing

/// A note's object links are read by FolioMarkdown and opened as FolioDomain's `AppLink`; neither module sees the
/// other, so the names they share are checked here, where both are.
struct AppLinkWikiTests {
    @Test func everyObjectLinkOpensAsAnAppLink() throws {
        let id = UUID()
        for kind in WikiLink.objectKinds.sorted() {
            let html = HTMLRenderer.render(markdown: "[[\(kind):\(id.uuidString)#page=2|글]]")
            let href = try #require(html.firstMatch(of: /href="([^"]+)"/)).1
            let link = try #require(AppLink(string: String(href)), "\(kind): \(href)")
            #expect(link.kind.rawValue == kind && link.id == id)
            #expect(AppLink.Kind(rawValue: kind) != nil)
        }
    }

    /// Every kind a link names by ID can be written in a note (`[[semester:<ID>]]`, `[[person:<ID>]]`), unless it is
    /// left out here on purpose.
    @Test func everyKindWithAnIDIsAnObjectLink() {
        let leftOut: Set<AppLink.Kind> = []
        let withID = Set(AppLink.Kind.allCases.filter { !$0.isPlace })
        #expect(Set(WikiLink.objectKinds) == Set(withID.subtracting(leftOut).map(\.rawValue)))
        #expect(leftOut.isSubset(of: withID))
    }

    @Test func aPageLinkKeepsItsPage() throws {
        let id = UUID()
        let html = HTMLRenderer.render(markdown: "[[material:\(id.uuidString)#page=12]]")
        let href = try #require(html.firstMatch(of: /href="([^"]+)"/)).1
        #expect(AppLink(string: String(href)) == AppLink(.material, id, anchor: .page(12)))
    }
}
