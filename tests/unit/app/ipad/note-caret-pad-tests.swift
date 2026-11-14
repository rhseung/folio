#if os(iOS)
import FolioDomain
import Testing
import UIKit
@testable import Folio

@MainActor @Suite(.serialized)
struct NoteCaretPadTests {
    @Test(arguments: ["본문\n# 11-10(화)\n", "본문\n# 11-10(화)\n\n끝"])
    func theCaretUnderAHeadingIsABodyCaret(_ text: String) async throws {
        let window = UIWindow(windowScene: try await NoteHangulPadTests.scene())
        window.frame = CGRect(x: 0, y: 0, width: 900, height: 720)
        let view = SourceTextView()
        view.frame = window.bounds
        window.addSubview(view)
        window.isHidden = false
        defer { window.isHidden = true }
        view.load(text)
        view.configure(accent: CourseAccent.presets[0].accent, syntax: .latex, dark: false)
        view.layoutIfNeeded()
        if let manager = view.textLayoutManager { manager.ensureLayout(for: manager.documentRange) }

        let ns = text as NSString
        let empty = text.hasSuffix("\n") ? ns.length : ns.range(of: "\n\n").location + 1
        let caret = { (i: Int) throws -> CGRect in
            view.caretRect(for: try #require(view.position(from: view.beginningOfDocument, offset: i)))
        }
        let body = try caret(0), heading = try caret(ns.range(of: "11-10").location), line = try caret(empty)
        #expect(heading.height > body.height)
        #expect(line.height == body.height, "caret \(line), body \(body)")
        #expect(line.minY >= heading.maxY, "caret \(line), heading \(heading)")
    }
}
#endif
