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

    /// A copied address between brackets (`[[folio://material/<ID>#page=2]]`) opens what the address does (#347).
    @Test func anAddressBetweenBracketsOpensAsItself() throws {
        let id = UUID()
        let links =
            AppLink.Kind.allCases.map { $0.isPlace ? AppLink.place($0) : AppLink($0, id) }
            + [
                AppLink(.material, id, anchor: .page(2)), AppLink(.note, id, anchor: .block("c1")),
                AppLink(.note, id, anchor: .heading("매칭 정리")),
                AppLink(.recording, id, anchor: .time(750)), .course(id, page: .units), .settings(.claude),
            ]
        for link in links {
            let html = HTMLRenderer.render(markdown: "[[\(link.string)]]")
            let href = try #require(html.firstMatch(of: /class="wikilink" href="([^"]+)"/)).1
            #expect(AppLink(string: String(href)) == link, "\(link.string): \(href)")
        }
    }

    @Test func aPageLinkKeepsItsPage() throws {
        let id = UUID()
        let html = HTMLRenderer.render(markdown: "[[material:\(id.uuidString)#page=12]]")
        let href = try #require(html.firstMatch(of: /href="([^"]+)"/)).1
        #expect(AppLink(string: String(href)) == AppLink(.material, id, anchor: .page(12)))
    }
}
