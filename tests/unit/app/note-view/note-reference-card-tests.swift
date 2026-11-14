import AppKit
import FolioDomain
import FolioFixtures
import FolioStorage
import Foundation
import Testing

@testable import Folio

@MainActor @Suite(.serialized, .timeLimit(.minutes(2)))
struct NoteReferenceCardTests {
    static let text = "앞 [[보조정리#^c1|그 식]] 뒤 [[보조정리]]\n[[보조정리#^long|긴 블록]]\n"

    func editor() throws -> (SourceTextView, NSWindow) {
        let gist = GISTStore(url: try Fixture.standard.copyToTemp())
        let store = try #require(try gist.courseStores().first { $0.url.lastPathComponent == "EC4207 그래프 이론" })
        try store.createNote(
            at: store.newNoteURL(title: "보조정리", format: .markdown),
            text: "위\n\n증명할 것 $x^2$ ^c1\n\n아래\n\n" + Array(repeating: "긴 줄", count: 80).joined(separator: "\n") + " ^long\n")
        let (view, window) = NoteAssistTests.editor(Self.text)
        view.cards = NoteEmbedSource(store: store, own: nil)
        return (view, window)
    }

    static func point(_ view: SourceTextView, at i: Int) throws -> NSPoint {
        let window = try #require(view.window)
        let rect = view.convert(
            window.convertFromScreen(view.firstRect(forCharacterRange: NSRange(location: i, length: 1), actualRange: nil)), from: nil)
        return NSPoint(x: rect.midX, y: rect.midY)
    }

    static func at(_ word: String) -> Int { (text as NSString).range(of: word).location }

    static func settle(_ view: SourceTextView) async {
        for _ in 0..<60 {
            try? await Task.sleep(for: .milliseconds(50))
            if view.card?.shown == true { break }
        }
    }

    @Test func restingOnAReferenceShowsItsBlock() async throws {
        let (view, window) = try editor()
        defer { withExtendedLifetime(window) {} }
        view.hover(at: try Self.point(view, at: Self.at("그 식")))
        try await Task.sleep(for: .milliseconds(150))
        #expect(view.card?.shown != true)
        await Self.settle(view)
        let card = try #require(view.card)
        #expect(card.shown)
        let text = try await card.web.callAsyncJavaScript("return document.body.textContent", contentWorld: .defaultClient) as? String
        #expect(text?.hasPrefix("증명할 것") == true && text?.contains("아래") == false, "\(text ?? "")")
        #expect(
            try await card.web.callAsyncJavaScript("return document.querySelectorAll('.katex').length", contentWorld: .defaultClient)
                as? Int == 1)
        let scroll = try #require(card.host.superview)
        let link = view.convert(try Self.point(view, at: Self.at("그 식")), to: scroll)
        let below = scroll.isFlipped ? card.host.frame.minY > link.y : card.host.frame.maxY < link.y
        #expect(below && card.host.frame.width == view.columnWidth && card.host.frame.height < 120, "\(card.host.frame)")

        view.hover(at: try Self.point(view, at: Self.at("뒤")))
        #expect(view.card?.shown == false)
        view.hover(at: try Self.point(view, at: Self.at("보조정리]]")))
        try await Task.sleep(for: .milliseconds(500))
        #expect(view.card?.shown == false)
    }

    @Test func aTallBlockFadesWhereItIsCut() async throws {
        let (view, window) = try editor()
        defer { withExtendedLifetime(window) {} }
        let cut = "return document.documentElement.classList.contains('cut')"
        view.hover(at: try Self.point(view, at: Self.at("긴 블록")))
        await Self.settle(view)
        let card = try #require(view.card)
        let scroll = try #require(card.host.superview)
        #expect(card.shown && card.host.frame.height == (scroll.bounds.height / 2).rounded(), "\(card.host.frame)")
        #expect(try await card.web.callAsyncJavaScript(cut, contentWorld: .defaultClient) as? Bool == true)
        view.hover(at: try Self.point(view, at: Self.at("뒤")))
        view.hover(at: try Self.point(view, at: Self.at("그 식")))
        await Self.settle(view)
        #expect(try await card.web.callAsyncJavaScript(cut, contentWorld: .defaultClient) as? Bool == false)
    }

    @Test func typingTakesTheCardAway() async throws {
        let (view, window) = try editor()
        defer { withExtendedLifetime(window) {} }
        view.hover(at: try Self.point(view, at: Self.at("그 식")))
        await Self.settle(view)
        #expect(view.card?.shown == true)
        NoteAssistTests.type(view, "x")
        #expect(view.card?.shown == false)
    }

    @Test func noCardOverTheCompletionMenu() async throws {
        let (view, window) = try editor()
        defer { withExtendedLifetime(window) {} }
        NoteAssistTests.type(view, "/")
        #expect(view.completion.visible)
        view.hover(at: try Self.point(view, at: Self.at("그 식")))
        try await Task.sleep(for: .milliseconds(800))
        #expect(view.card?.shown != true)
    }

    @Test func noCardWhileASyllableIsComposed() async throws {
        let (view, window) = try editor()
        defer { withExtendedLifetime(window) {} }
        view.setMarkedText("ㄱ", selectedRange: NSRange(location: 1, length: 0), replacementRange: NoteAssistTests.none)
        view.hover(at: try Self.point(view, at: Self.at("그 식")))
        try await Task.sleep(for: .milliseconds(800))
        #expect(view.card?.shown != true)
        #expect(view.hasMarkedText())
    }
}
