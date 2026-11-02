import AppKit
import SwiftUI
import Testing
@testable import Folio

/// A page doesn't stretch past its ends: the bounce pulled its backdrop off the panel's top edge.
@MainActor @Suite(.serialized)
struct PageScrollTests {
    @Observable final class Rows { var count = 40 }

    // Reads `rows` in its body, so a change redraws the page; read where the host is built, it was a fixed value.
    struct Rig: View {
        let rows: Rows
        var body: some View { Page { ForEach(0..<rows.count, id: \.self) { Text("줄 \($0)") } } }
    }

    static func scrollViews(in view: NSView) -> [NSScrollView] {
        ((view as? NSScrollView).map { [$0] } ?? []) + view.subviews.flatMap(scrollViews)
    }

    static func settle(_ host: NSView) async throws {
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
    }

    @Test func pageDoesNotBounce() async throws {
        let rows = Rows()
        let host = NSHostingView(rootView: Rig(rows: rows))
        let window = NSWindow(contentRect: CGRect(x: -20_000, y: -20_000, width: 600, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        try await Self.settle(host)

        let scroll = try #require(Self.scrollViews(in: host).first)
        #expect(scroll.verticalScrollElasticity == .none)
        #expect(scroll.horizontalScrollElasticity == .none)

        // It stays off when SwiftUI redraws the page for new content.
        let height = try #require(scroll.documentView).frame.height
        rows.count = 80
        try await Self.settle(host)
        #expect(try #require(scroll.documentView).frame.height > height)
        #expect(scroll.verticalScrollElasticity == .none)
        #expect(scroll.horizontalScrollElasticity == .none)
    }
}
