#if os(macOS)
import AppKit
import FolioFixtures
import PDFKit
import Testing
@testable import Folio

/// A PDF pane made narrower or wider stays on the page it showed (#62): two panes merging halved a lecture's pane and
/// its next page came up in its place.
@MainActor @Suite(.serialized)
struct PDFWidthTests {
    // Low enough that a page fills most of the view at every width, so the page shown is the one in view.
    static let height: CGFloat = 200

    @Test func aNarrowerOrWiderPaneKeepsThePage() async throws {
        let (controller, view, window) = try await pane()
        for width: CGFloat in [400, 320, 900, 640] {
            view.setFrameSize(CGSize(width: width, height: Self.height))
            try await settle(view)
            #expect(controller.page == 4, "at \(width)pt")
        }
        _ = window
    }

    // A divider dragged changes the width a little at every frame. In a pane tall enough for a few pages, as in the
    // window, the snapshots caught page 6 sliding to page 9.
    @Test func aDividerDraggedFrameByFrameKeepsThePage() async throws {
        let (controller, view, window) = try await pane(height: 800)
        for direction: CGFloat in [-1, 1] {
            for _ in 1...16 {
                view.setFrameSize(CGSize(width: view.frame.width + direction * 16, height: 800))
                view.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(16))
            }
            try await settle(view)
            #expect(controller.page == 4, "after a drag to \(view.frame.width)pt")
            #expect(topPage(of: view) == 4, "after a drag to \(view.frame.width)pt")
        }
        _ = window
    }

    // Panes gliding into place nudge the width by a fraction of a point for a second or so.
    @Test func aWidthNudgedByLessThanAPointKeepsThePage() async throws {
        let (controller, view, window) = try await pane(height: 800)
        for step in 0..<60 {
            view.setFrameSize(CGSize(width: 400 + CGFloat(step % 3) * 0.3, height: 800))
            view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(8))
        }
        try await settle(view)
        #expect(controller.page == 4)
        #expect(topPage(of: view) == 4)
        _ = window
    }

    // A pane opening goes to its page before it has a width.
    @Test func aPaneOpenedOnAPageShowsThatPage() async throws {
        let document = try #require(PDFDocument(data: SampleLecture.data()))
        let controller = PDFController(document: document, page: 4)
        let view = controller.view
        view.frame = .zero
        let host = NSView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        let window = NSWindow(
            contentRect: CGRect(x: -20_000, y: -20_000, width: 1000, height: 800), styleMask: [.borderless],
            backing: .buffered, defer: false)
        window.contentView = host
        host.addSubview(view)
        controller.restore()
        try await Task.sleep(for: .milliseconds(16))
        view.setFrameSize(CGSize(width: 400, height: 800))
        try await settle(view)
        #expect(controller.page == 4)
        #expect(topPage(of: view) == 4)
    }

    func topPage(of view: PDFView) -> Int? {
        guard let document = view.document,
            let page = view.page(
                for: CGPoint(x: view.bounds.midX, y: view.isFlipped ? view.bounds.minY + 8 : view.bounds.maxY - 8), nearest: true)
        else { return nil }
        return document.index(for: page)
    }

    func pane(height: CGFloat = PDFWidthTests.height) async throws -> (PDFController, PDFView, NSWindow) {
        let document = try #require(PDFDocument(data: SampleLecture.data()))
        let controller = PDFController(document: document, page: 0)
        let view = controller.view
        view.frame = CGRect(x: 0, y: 0, width: 640, height: height)
        let host = NSView(frame: CGRect(x: 0, y: 0, width: 1000, height: height))
        host.addSubview(view)
        let window = NSWindow(
            contentRect: CGRect(x: -20_000, y: -20_000, width: 1000, height: height), styleMask: [.borderless],
            backing: .buffered, defer: false)
        window.contentView = host
        try await settle(view)
        controller.go(to: 4)
        try await settle(view)
        #expect(controller.page == 4)
        #expect(topPage(of: view) == 4)
        return (controller, view, window)
    }

    func settle(_ view: NSView) async throws {
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .seconds(SteadyPDFView.settling + 0.15))
        view.layoutSubtreeIfNeeded()
    }
}
#endif
