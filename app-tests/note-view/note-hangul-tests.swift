import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Folio

/// 선형대수학 in the standard fixture, with its rough note 03-03(화).
private let linearAlgebra = UUID(uuidString: "C0000000-0000-4000-8000-000000000001")!

/// Hangul typed into the edit view as the Korean input method types it, with SwiftUI updating the view and the note
/// saving between keys: the syllable being composed stays whole, and every finished one lands in the note's file.
@MainActor @Suite(.serialized, .timeLimit(.minutes(5)))
struct NoteHangulTests {
    enum Key: CustomStringConvertible {
        /// The syllable being composed, shown marked.
        case compose(String)
        /// A finished syllable, typed in place of the marked one.
        case commit(String)
        /// The syllable ends without a key: a click elsewhere, another window.
        case leave

        var description: String {
            switch self {
            case .compose(let s): "compose \(s)"
            case .commit(let s): "commit \(s)"
            case .leave: "leave"
            }
        }
    }

    /// 하나 한글다, jamo by jamo. ㅏ after 한 moves its ㄴ on to the next syllable, as the input method does.
    static let keys: [Key] = [
        .compose("ㅎ"), .compose("하"), .compose("한"), .commit("하"), .compose("나"), .commit("나"), .commit(" "),
        .compose("ㅎ"), .compose("하"), .compose("한"), .commit("한"), .compose("ㄱ"), .compose("그"), .compose("글"), .commit("글"),
        .compose("ㄷ"), .compose("다"), .leave,
    ]

    static let none = NSRange(location: NSNotFound, length: 0)

    @Test(arguments: ["end", "middle"])
    func syllablesSurviveUpdatesAndSavesAndLandInTheNote(_ place: String) async throws {
        let workspace = try fixtureWorkspace()
        let course = try #require(workspace.course(linearAlgebra))
        let notes = NotesModel(workspace: workspace, course: course)
        let file = try #require(notes.note(workspace.noteId(titled: "03-03(화)", in: course)))
        let model = NoteEditorModel(workspace: workspace, course: course, note: file)
        model.load()
        if !model.body.contains("\n") { model.body += "\n둘째 줄" }

        let bench = NoteBench(.edit, text: Binding(get: { model.body }, set: { model.body = $0 }), baseURL: model.baseURL)
        await bench.settle()
        bench.focus()
        let input = try #require(bench.input)
        let start = model.body as NSString
        // At the end of the note, or at the end of its first line, with text after.
        let caret = place == "end" ? start.length : start.range(of: "\n").location
        bench.perform(#selector(NSResponder.moveToBeginningOfDocument(_:)))
        bench.perform(place == "end" ? #selector(NSResponder.moveToEndOfDocument(_:)) : #selector(NSResponder.moveToEndOfParagraph(_:)))
        try #require(input.selectedRange() == NSRange(location: caret, length: 0))
        let before = start.substring(to: caret), after = start.substring(from: caret)

        var typed = "", marked = ""
        for (n, key) in Self.keys.enumerated() {
            switch key {
            case .compose(let s):
                input.setMarkedText(s, selectedRange: NSRange(location: (s as NSString).length, length: 0), replacementRange: Self.none)
                marked = s
            case .commit(let s):
                input.insertText(s, replacementRange: Self.none)
                typed += s
                marked = ""
            case .leave:
                input.unmarkText()
                typed += marked
                marked = ""
            }
            let step = "\(place), key \(n) (\(key))"
            await bench.update()
            #expect(bench.text == before + typed + marked + after, "\(step) after an update")
            model.saveNow(force: false)
            await bench.update()
            #expect(bench.text == before + typed + marked + after, "\(step) after saving")
            #expect(input.hasMarkedText() == !marked.isEmpty, "\(step)")
            if !marked.isEmpty {
                #expect(input.attributedSubstring(forProposedRange: input.markedRange(), actualRange: nil)?.string == marked, "\(step)")
            }
            // The note has every finished syllable; the one being composed may come later.
            #expect(model.body.hasPrefix(before + typed), "\(step): \(model.body.debugDescription)")
        }
        #expect(model.body == before + "하나 한글다" + after)
        model.saveNow(force: false)
        let saved = try String(contentsOf: file.url, encoding: .utf8)
        #expect(saved.contains(before + "하나 한글다" + after))
    }
}
