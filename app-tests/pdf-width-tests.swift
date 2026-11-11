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
        let document = try #require(PDFDocument(data: SampleLecture.data()))
        let controller = PDFController(document: document, page: 0)
        let view = controller.view
        view.frame = CGRect(x: 0, y: 0, width: 640, height: Self.height)
        let host = NSView(frame: CGRect(x: 0, y: 0, width: 1000, height: Self.height))
        host.addSubview(view)
        let window = NSWindow(contentRect: CGRect(x: -20_000, y: -20_000, width: 1000, height: Self.height), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = host
        try await settle(view)
        controller.go(to: 4)
        try await settle(view)
        #expect(controller.page == 4)
        for width: CGFloat in [400, 320, 900, 640] {
            view.setFrameSize(CGSize(width: width, height: Self.height))
            try await settle(view)
            #expect(controller.page == 4, "at \(width)pt")
        }
    }

    func settle(_ view: NSView) async throws {
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        view.layoutSubtreeIfNeeded()
    }
}
#endif
