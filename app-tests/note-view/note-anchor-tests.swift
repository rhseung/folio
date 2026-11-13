import AppKit
import FolioDomain
import Foundation
import SwiftUI
import Testing

@testable import Folio

/// A note opened by a link to a heading or block, in the write view: the caret goes to that line, and the line comes
/// on screen.
@MainActor @Suite(.serialized)
struct NoteAnchorRevealTests {
    let note = NoteBench.longNote

    @Test func aHeadingLinkPutsTheCaretOnItsLineOnScreen() async throws {
        let bench = NoteBench(.edit, note, anchor: .heading("Hall의 조건"))
        await bench.settle()
        let caret = try #require(bench.caret)
        #expect(caret.location == (note as NSString).range(of: "## Hall의 조건").location)
        // Far enough down the note that it was off screen when opened.
        #expect(bench.scrollY > 0)
        #expect(caret.rect.minY >= 0 && caret.rect.maxY <= bench.size.height / 3, "\(caret.rect)")
        // Drawn there too, not only laid out: the scroller coming in narrows the column after the line is placed.
        #expect(bench.snapshot().ink(in: CGRect(x: 0, y: caret.rect.minY, width: bench.size.width, height: caret.rect.height)) > 0)
    }

    @Test func theNoteArrivingAfterTheViewStillReachesTheHeading() async throws {
        // The note screen's model reads the file after the view is made, so the editor first sees no text.
        let text = NoteBench.Note("")
        let bench = NoteBench(.edit, text: Binding(get: { text.text }, set: { text.text = $0 }), anchor: .heading("Tutte의 정리"))
        await bench.settle()
        text.text = note
        await bench.settle()
        let caret = try #require(bench.caret)
        #expect(caret.location == (note as NSString).range(of: "### Tutte의 정리").location)
        #expect(caret.rect.minY >= 0 && caret.rect.maxY <= bench.size.height / 3, "\(caret.rect)")
    }

    @Test func goingBackAndForwardToTheSameHeadingMovesTheCaretAgain() async throws {
        // Opened from the sidebar, then a link to a heading, back (no anchor), and forward: the view stays the same one.
        let bench = NoteBench(.edit, note)
        await bench.settle()
        let heading = (note as NSString).range(of: "## Hall의 조건").location
        bench.anchor = .heading("Hall의 조건")
        await bench.settle()
        #expect(bench.caret?.location == heading)
        bench.anchor = nil
        await bench.settle()
        bench.placeCaret(at: 0)
        await bench.scroll(to: 0)
        bench.anchor = .heading("Hall의 조건")
        await bench.settle()
        let caret = try #require(bench.caret)
        #expect(caret.location == heading)
        #expect(caret.rect.minY >= 0 && caret.rect.maxY <= bench.size.height / 3, "\(caret.rect)")
    }

    @Test func aMissingHeadingOpensAtTheTop() async throws {
        let bench = NoteBench(.edit, note, anchor: .heading("없는 제목"))
        await bench.settle()
        // The caret stays wherever loading the text left it, as for a note opened without a link.
        #expect(bench.scrollY == 0)
    }
}
