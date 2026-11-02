import AppKit
import SwiftUI
import Testing
@testable import Folio

/// A page doesn't stretch past its ends: the bounce pulled its backdrop off the panel's top edge.
@MainActor @Suite(.serialized)
struct PageScrollTests {
    @Observable final class Rows { var count = 40 }

    static func scrollViews(in view: NSView) -> [NSScrollView] {
        ((view as? NSScrollView).map { [$0] } ?? []) + view.subviews.flatMap(scrollViews)
    }

    @Test func pageDoesNotBounce() async throws {
        let rows = Rows()
        let host = NSHostingView(rootView: Page { ForEach(0..<rows.count, id: \.self) { Text("줄 \($0)") } })
        let window = NSWindow(contentRect: CGRect(x: -20_000, y: -20_000, width: 600, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))

        let scroll = try #require(Self.scrollViews(in: host).first)
        #expect(scroll.verticalScrollElasticity == .none)

        // It stays off when SwiftUI updates the scroll view for new content.
        rows.count = 80
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        #expect(scroll.verticalScrollElasticity == .none)
    }
}
