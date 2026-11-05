import AppKit
import FolioDomain
import FolioMarkdown
import Foundation
import SwiftUI
import Testing
@testable import Folio

/// The write view: the markdown source styled in place, laid out by TextKit as in the app.
@MainActor @Suite(.serialized)
struct NoteSourceTests {
    static func editor(_ text: String, width: CGFloat = 900, dark: Bool = false) -> (SourceTextView, NSWindow) {
        let view = SourceTextView()
        view.delegate = view
        let window = NoteRender.host(view, width: width, dark: dark)
        view.baseURL = NoteRender.fixtures
        view.load(text)
        view.configure(accent: CourseAccent.presets[0].accent, syntax: .latex, dark: dark)
        NoteRender.layout(view)
        return (view, window)
    }

    static var sample: String {
        let url = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "fixtures/all-markdown.md")
        return Frontmatter.split((try? String(contentsOf: url, encoding: .utf8)) ?? "").body
    }

    /// The caret is one height on every body line, empty or holding smaller code, and stands over the text, not the
    /// whole line: the line's gap is above the text, and a caret through it reached up to the line before.
    @Test func linesAreOneHeightWithTheCaretOverTheText() throws {
        let text = "본문 줄\n\n`code` 섞인 줄\n> 인용\n## 제목\n끝"
        let (view, _) = Self.editor(text)
        let ns = text as NSString
        let body = try #require(NoteRender.caret(view, at: 0))
        let manager = try #require(view.textLayoutManager)
        let line = try #require(manager.textLayoutFragment(for: manager.documentRange.location)).layoutFragmentFrame
        #expect(body.height < line.height)
        for i in [ns.range(of: "\n\n").location + 1, ns.range(of: "섞인").location, ns.range(of: "인용").location, ns.range(of: "끝").location] {
            #expect(try #require(NoteRender.caret(view, at: i)).height == body.height)
        }
        #expect(try #require(NoteRender.caret(view, at: ns.range(of: "제목").location)).height > body.height)
        for word in ["본문", "섞인", "인용", "제목", "끝"] {
            let at = ns.range(of: word).location
            let caret = try #require(NoteRender.caret(view, at: at)), drawn = try #require(NoteRender.text(view, at: at))
            #expect(abs(caret.minY - drawn.lowerBound) <= 1 && abs(caret.maxY - drawn.upperBound) <= 1, "\(word): caret \(caret), text \(drawn)")
        }
    }

    static func typing(_ text: String) -> (SourceTextView, NSWindow) {
        let (view, window) = editor(text)
        window.makeFirstResponder(view)
        view.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        return (view, window)
    }

    static func size(_ view: NSTextView, at i: Int) -> CGFloat? {
        (view.textStorage?.attribute(.font, at: i, effectiveRange: nil) as? NSFont)?.pointSize
    }

    /// In the source only headings change the text size: code, math, task boxes and callout labels stay body size.
    @Test func onlyHeadingsChangeTheSize() throws {
        let (view, _) = Self.editor(Self.sample)
        let storage = try #require(view.textStorage)
        let ns = storage.string as NSString
        var odd: [String] = []
        storage.enumerateAttribute(.font, in: NSRange(location: 0, length: storage.length)) { value, r, _ in
            let font = value as? NSFont
            // Monospaced type is scaled to read as the same size.
            let size = (font?.pointSize ?? 0) / (font?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true ? NoteLook.monoScale : 1)
            let line = ns.substring(with: ns.lineRange(for: r))
            let heading = line.hasPrefix("#")
            if size != NoteLook.body, !(heading && NoteLook.headingSizes.contains(size)) { odd.append("\(size) \(ns.substring(with: r).debugDescription)") }
        }
        #expect(odd.isEmpty, "\(odd.prefix(5))")
    }

    @Test func hangulBeingComposedIsBodySized() throws {
        for text in ["- 하나", "본문", "## 제목"] {
            let (view, _) = Self.typing(text)
            view.insertNewline(nil)
            view.setMarkedText("하", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            #expect(Self.size(view, at: view.markedRange().location) == NoteLook.body, "\(text)")
            view.unmarkText()
            #expect(Self.size(view, at: view.string.utf16.count - 1) == NoteLook.body, "\(text)")
        }
        let (view, _) = Self.typing("## 제목")
        view.setMarkedText("하", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(Self.size(view, at: view.markedRange().location) == NoteLook.headingSizes[1])
    }

    /// The binding gets the text only once a syllable is done, so a SwiftUI update in between sees the editor ahead of it.
    @Test func aSyllableBeingComposedSurvivesTheEditorUpdating() throws {
        final class Box {
            var text = "가"
            var insert: String?
        }
        let box = Box()
        let editor = MarkdownEditor(text: Binding(get: { box.text }, set: { box.text = $0 }), baseURL: nil, math: .latex,
                                    insert: Binding(get: { box.insert }, set: { box.insert = $0 }), saveFile: { _, _ in nil }, openNote: { _ in })
        let coordinator = editor.makeCoordinator()
        let (view, window) = Self.editor(box.text)
        view.onChange = { coordinator.changed() }
        coordinator.view = view
        let accent = CourseAccent.presets[0].accent
        window.makeFirstResponder(view)
        view.setSelectedRange(NSRange(location: 1, length: 0))
        let none = NSRange(location: NSNotFound, length: 0)
        view.setMarkedText("ㄴ", selectedRange: NSRange(location: 1, length: 0), replacementRange: none)
        editor.update(view, coordinator, accent: accent, dark: false)
        #expect(view.string == "가ㄴ" && view.hasMarkedText())
        view.setMarkedText("나", selectedRange: NSRange(location: 1, length: 0), replacementRange: none)
        editor.update(view, coordinator, accent: accent, dark: false)
        #expect(view.string == "가나")
        // Leaving the window ends the syllable without a keystroke.
        view.unmarkText()
        #expect(box.text == "가나")
    }

    /// Enter then Tab under `- 셋` starts a sub-item; CommonMark alone would make `셋` a heading until it has text.
    @Test func startingASubItemKeepsTheItemAbove() throws {
        let (view, _) = Self.typing("- 하나\n- 셋")
        view.insertNewline(nil)
        view.insertTab(nil)
        #expect(view.string == "- 하나\n- 셋\n    - ")
        let item = (view.string as NSString).range(of: "셋").location
        #expect(Self.size(view, at: item) == NoteLook.body)
        #expect(Self.size(view, at: item) == Self.size(view, at: (view.string as NSString).range(of: "하나").location))
        view.insertText("넷", replacementRange: view.selectedRange())
        #expect(Self.size(view, at: item) == NoteLook.body)
    }

    @Test func renderSample() {
        for dark in [false, true] {
            let (view, _) = Self.editor(Self.sample, dark: dark)
            NoteRender.write(view, "source-\(dark ? "dark" : "light")")
        }
    }

    /// Drawn under their line, a math block and an image made the note taller than its text, and the view couldn't
    /// scroll to a picture under the last line. Against the same source that renders nothing, the height is the same.
    @Test func mathBlocksAndImagesAddNoHeight() throws {
        func height(_ text: String) throws -> CGFloat {
            let (view, _) = Self.editor(text)
            return try #require(view.textLayoutManager).usageBoundsForTextContainer.height
        }
        let shown = try height("앞\n$$\nx^2\n$$\n![a](assets/sample.png)")
        let unshown = try height("앞\n$$\n\\frac{\n$$\n![a](assets/missing.png)")
        #expect(shown == unshown)
    }

    @Test func theBubbleShowsMathBlocksAndImagesByTheCaret() throws {
        let text = "앞 $y$\n$$\nx^2\n$$\n![a](assets/sample.png)"
        let (view, window) = Self.editor(text)
        window.makeFirstResponder(view)
        let ns = text as NSString
        func bubble(at i: Int) -> PreviewBubble? {
            view.setSelectedRange(NSRange(location: i, length: 0))
            return view.subviews.compactMap { $0 as? PreviewBubble }.first
        }
        #expect(bubble(at: 0) == nil)
        #expect(bubble(at: ns.range(of: "$y").location + 1) != nil)
        #expect(bubble(at: ns.range(of: "x^2").location) != nil)
        // On the note's last line there's no room under it, so the bubble goes over it, where the view still shows it.
        let image = try #require(bubble(at: ns.range(of: "sample").location))
        #expect(image.frame.maxY <= view.bounds.maxY && image.frame.minY >= 0, "\(image.frame) in \(view.bounds)")
    }

    @Test func theBubbleTakesItsWindowsLook() throws {
        let card = { (name: NSAppearance.Name) -> CGColor? in
            var color: CGColor?
            NSAppearance(named: name)?.performAsCurrentDrawingAppearance { color = NoteLook.card.cgColor }
            return color
        }
        for (look, other) in [(NSAppearance.Name.aqua, NSAppearance.Name.darkAqua), (.darkAqua, .aqua)] {
            let bubble = PreviewBubble(image: NSImage(size: NSSize(width: 20, height: 10)), size: CGSize(width: 20, height: 10))
            bubble.appearance = NSAppearance(named: look)
            // Whatever the app's appearance is while the layer is updated, the bubble's own decides.
            NSAppearance(named: other)?.performAsCurrentDrawingAppearance { bubble.updateLayer() }
            #expect(bubble.layer?.backgroundColor == card(look))
        }
    }
}
