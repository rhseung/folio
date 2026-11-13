import AppKit
import FolioDomain
import Foundation
import SwiftUI
import Testing

@testable import Folio

@MainActor @Suite(.serialized)
struct NoteAnchorRevealTests {
    let note = NoteBench.longNote

    @Test func aHeadingLinkPutsTheCaretOnItsLineOnScreen() async throws {
        let bench = NoteBench(.edit, note, anchor: .heading("Hall의 조건"))
        await bench.settle()
        let caret = try #require(bench.caret)
        #expect(caret.location == (note as NSString).range(of: "## Hall의 조건").location)
        #expect(bench.scrollY > 0)
        #expect(caret.rect.minY >= 0 && caret.rect.maxY <= bench.size.height / 3, "\(caret.rect)")
        // 스크롤 막대가 나타나면 줄을 배치한 뒤에 열 폭이 줄어들므로, 배치만이 아니라 실제로 그려졌는지도 확인한다.
        #expect(bench.snapshot().ink(in: CGRect(x: 0, y: caret.rect.minY, width: bench.size.width, height: caret.rect.height)) > 0)
    }

    @Test func theNoteArrivingAfterTheViewStillReachesTheHeading() async throws {
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
        #expect(bench.scrollY == 0)
    }
}
