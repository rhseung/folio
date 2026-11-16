import FolioMarkdown
import Foundation
import Testing

@testable import Folio

@MainActor @Suite(.serialized)
struct CompletionMenuTests {
    // 링크 후보는 늦게 오므로, 검색이 고른 순서가 메뉴의 맨 위까지 닿는지 늦게 오는 길로 본다.
    static let found: [String: [String]] = ["Matri": ["matrix", "Matrix"], "Matrix": ["Matrix", "matrix"]]

    static func menu() -> CompletionMenu {
        let menu = CompletionMenu()
        menu.more = { query in
            (found[query.text] ?? []).map { CompletionItem(id: "link.\($0)", title: $0, body: $0) }
        }
        return menu
    }

    static func type(_ typed: String, into menu: CompletionMenu) async {
        let text = "[[" + typed
        guard let query = Completion.query(in: text as NSString, caret: text.utf16.count, catalog: CompletionCatalog()) else {
            Issue.record("no link query for \(text)")
            return
        }
        await withCheckedContinuation { done in
            menu.arrived = { done.resume() }
            menu.show(query, [])
        }
    }

    @Test func aLateTopFollowsTheTypedCase() async {
        let menu = Self.menu()
        await Self.type("Matri", into: menu)
        #expect(menu.current?.title == "matrix")
        await Self.type("Matrix", into: menu)
        #expect(menu.current?.title == "Matrix")
    }

    @Test func aLatePickMovedByHandStays() async {
        let menu = Self.menu()
        await Self.type("Matri", into: menu)
        menu.move(1)
        #expect(menu.current?.title == "Matrix")
        await Self.type("Matrix", into: menu)
        #expect(menu.current?.title == "Matrix" && menu.selected == 0)
        menu.move(1)
        await Self.type("Matrix", into: menu)
        #expect(menu.current?.title == "matrix")
    }
}
