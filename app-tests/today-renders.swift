import AppKit
import FolioFixtures
import SwiftUI
import Testing
@testable import Folio

/// Today for every scenario, light and dark, wide and narrow, as PNGs in FOLIO_RENDER_DIR (mise run render).
/// Skipped without it, so `mise run test-app` stays quick.
@MainActor @Suite(.serialized)
struct TodayRenders {
    nonisolated static let folder = ProcessInfo.processInfo.environment["FOLIO_RENDER_DIR"].map { URL(filePath: $0, directoryHint: .isDirectory) }

    @Test(.enabled(if: folder != nil), arguments: Scenario.allCases)
    func today(_ scenario: Scenario) async throws {
        let folder = try #require(Self.folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let workspace = try Workspace.scenario(scenario)
        // 720 is under the width where deadlines leave their side column.
        for width in [1180, 720] {
            for scheme in [ColorScheme.light, .dark] {
                let png = try await renderOffscreen(TodayView(workspace: workspace).environment(workspace), width: CGFloat(width), scheme: scheme)
                try png.write(to: folder.appending(path: "today-\(scenario.rawValue)-\(width)-\(scheme == .dark ? "dark" : "light").png"))
            }
        }
    }
}

/// `ImageRenderer` can't draw AppKit-backed controls (the quick-add field, menus) and never runs `.task`, which loads
/// the study chart, so the view goes in a window that is never ordered on screen and is drawn with `cacheDisplay`.
@MainActor
func renderOffscreen(_ view: some View, width: CGFloat, scheme: ColorScheme) async throws -> Data {
    let host = NSHostingView(rootView: view.environment(\.colorScheme, scheme))
    // Far off every display and fully transparent: ordered in only because SwiftUI runs `.task` for views on screen.
    let window = NSWindow(contentRect: CGRect(x: -20_000, y: -20_000, width: width, height: 900), styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
    window.alphaValue = 0
    window.ignoresMouseEvents = true
    window.contentView = host
    window.orderFrontRegardless()
    defer { window.orderOut(nil) }
    try await settle()
    // Pages scroll, so the window takes the scrolled content's height to draw all of it.
    if let height = host.firstScrollView?.documentView?.frame.height, height > 0 {
        window.setContentSize(CGSize(width: width, height: height))
        try await settle()
    }
    let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: rep)
    return try #require(rep.representation(using: .png, properties: [:]))
}

/// Lets layout, `.task` and `onGeometryChange` settle before drawing. A sleep, not a nested run loop: the loop would run
/// while this test still holds the main actor, so a `.task` resuming on it (the study chart's load) waits until after the draw.
private func settle() async throws {
    try await Task.sleep(for: .milliseconds(500))
}

private extension NSView {
    var firstScrollView: NSScrollView? {
        (self as? NSScrollView) ?? subviews.lazy.compactMap(\.firstScrollView).first
    }
}
