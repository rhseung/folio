#if os(macOS)
import AppKit
import FolioFixtures
import PDFKit
import Testing
@testable import Folio

@MainActor @Suite(.serialized)
struct PDFWidthTests {
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

    // 칸이 제자리로 움직이는 동안 1초 남짓 폭이 1pt보다 작게 흔들린다.
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

    // 다른 작업이 main 스레드를 붙잡으면 PDFKit이 폭에 맞춰 현재 쪽을 다시 고르는 일이 놓은 뒤로 밀린다. CI의 전체 테스트에서는 다른 suite가 이렇게 붙잡았다.
    // 이 테스트 안에서 바로 막으면 PDFKit의 다시 고르기가 놓기보다 먼저 끝나서 재현되지 않으므로, 따로 띄운 작업이 막는다.
    @Test(arguments: [0, 4, 16]) func aBusyMainThreadAfterAWidthChangeKeepsThePage(after delay: Int) async throws {
        let (controller, view, window) = try await pane(height: 800)
        for width: CGFloat in [400, 400.3, 400.6] {
            view.setFrameSize(CGSize(width: width, height: 800))
            view.layoutSubtreeIfNeeded()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(delay))
                usleep(useconds_t((SteadyPDFView.settling + 0.1) * 1_000_000))
            }
            try await Task.sleep(for: .milliseconds(8))
            try await settle(view)
            #expect(controller.page == 4, "at \(width)pt")
            #expect(topPage(of: view) == 4, "at \(width)pt")
        }
        _ = window
    }

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
