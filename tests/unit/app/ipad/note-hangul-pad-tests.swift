#if os(iOS)
import SwiftUI
import Testing
import UIKit
@testable import Folio

/// Hangul typed into the iPad's edit view, with SwiftUI updating the view between keys: the syllable being composed
/// stays whole, and every finished one reaches the note. The Mac's `NoteHangulTests` does the same, saving too.
@MainActor @Suite(.serialized)
struct NoteHangulPadTests {
    @Observable final class Note {
        var text: String
        init(_ text: String) { self.text = text }
    }

    @Observable final class Pulse {
        var count = 0
    }

    struct Rig: View {
        let note: Note
        let pulse: Pulse
        @State private var insert: String?

        var body: some View {
            let count = pulse.count
            // `saveFile` names the update it came with, so a step can tell SwiftUI handed it to the view.
            MarkdownEditor(
                text: Binding(get: { note.text }, set: { note.text = $0 }), baseURL: nil, math: .latex, insert: $insert,
                saveFile: { _, _ in "update \(count)" }, openNote: { _ in }
            )
            .environment(\.accent, CourseAccent.presets[0].accent)
        }
    }

    enum Key: CustomStringConvertible {
        case compose(String)
        /// The syllable is done: the marked one becomes `s`, then text.
        case commit(String)
        /// Typed with nothing composing.
        case plain(String)
        /// The syllable ends without a key: a tap elsewhere, the app leaving.
        case leave

        var description: String {
            switch self {
            case .compose(let s): "compose \(s)"
            case .commit(let s): "commit \(s)"
            case .plain(let s): "type \(s)"
            case .leave: "leave"
            }
        }
    }

    /// 하나 한글다, jamo by jamo. ㅏ after 한 moves its ㄴ on to the next syllable.
    static let keys: [Key] = [
        .compose("ㅎ"), .compose("하"), .compose("한"), .commit("하"), .compose("나"), .commit("나"), .plain(" "),
        .compose("ㅎ"), .compose("하"), .compose("한"), .commit("한"), .compose("ㄱ"), .compose("그"), .compose("글"), .commit("글"),
        .compose("ㄷ"), .compose("다"), .leave,
    ]

    static func scene() async throws -> UIWindowScene {
        for _ in 0..<100 {
            if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first { return scene }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw CancellationError()
    }

    static func editor(in view: UIView) -> SourceTextView? {
        (view as? SourceTextView) ?? view.subviews.lazy.compactMap(editor).first
    }

    static func settle(_ window: UIWindow) async {
        for _ in 0..<4 {
            window.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test(arguments: ["end", "middle"])
    func syllablesSurviveUpdatesAndLandInTheNote(_ place: String) async throws {
        let start = "# 첫 줄\n둘째 줄의 본문"
        let note = Note(start), pulse = Pulse()
        let window = UIWindow(windowScene: try await Self.scene())
        window.frame = CGRect(x: 0, y: 0, width: 900, height: 720)
        window.rootViewController = UIHostingController(rootView: Rig(note: note, pulse: pulse))
        window.isHidden = false
        defer { window.isHidden = true }
        await Self.settle(window)
        let view = try #require(Self.editor(in: window))
        #expect(view.becomeFirstResponder())
        let ns = start as NSString
        let caret = place == "end" ? ns.length : ns.range(of: "\n").location
        view.selectedRange = NSRange(location: caret, length: 0)
        let before = ns.substring(to: caret), after = ns.substring(from: caret)

        var typed = "", marked = ""
        for (n, key) in Self.keys.enumerated() {
            switch key {
            case .compose(let s):
                view.setMarkedText(s, selectedRange: NSRange(location: (s as NSString).length, length: 0))
                marked = s
            case .commit(let s):
                view.setMarkedText(s, selectedRange: NSRange(location: (s as NSString).length, length: 0))
                view.unmarkText()
                typed += s
                marked = ""
            case .plain(let s):
                view.insertText(s)
                typed += s
            case .leave:
                view.unmarkText()
                typed += marked
                marked = ""
            }

            let step = "\(place), key \(n) (\(key))"
            pulse.count += 1
            await Self.settle(window)
            #expect(view.saveFile("", Data()) == "update \(pulse.count)", "\(step): SwiftUI didn't update the view")
            #expect(view.text == before + typed + marked + after, "\(step): \(view.text.debugDescription)")
            #expect((view.markedTextRange != nil) == !marked.isEmpty, "\(step)")
            if let range = view.markedTextRange { #expect(view.text(in: range) == marked, "\(step)") }
            #expect(note.text.hasPrefix(before + typed), "\(step): the note holds \(note.text.debugDescription)")
        }
        #expect(note.text == before + "하나 한글다" + after)
    }
}
#endif
