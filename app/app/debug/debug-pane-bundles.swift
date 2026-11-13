#if DEBUG
import FolioDomain
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Debug-only (`FOLIO_PANE_BUNDLES=<folder>` with a fake `FOLIO_GIST`): the pictures of #62's side bundles, without any
/// input. A tab gets five panes and is pressed so the panes without room fold into one bundle, then a bundle at either
/// end, then a one-pane bundle beside a bigger one whose list is opened; a second tab of three panes has its middle
/// one folded by hand. Each step is drawn into the folder as `<step>.png` with what every pane shows in `panes.txt`,
/// and the app quits. On a Mac the window is `FOLIO_SNAPSHOT_WIDTH` wide (the hand-folded step 1280, so two panes
/// stay open beside the strip); on an iPad it is the simulator's.
@MainActor enum PaneBundleProbe {
    static let folder = ProcessInfo.processInfo.environment["FOLIO_PANE_BUNDLES"].map { URL(filePath: $0, directoryHint: .isDirectory) }

    static func run(tabs: WindowTabs, workspace: Workspace) async {
        guard let folder else { return }
        // folio:not-an-action debug screenshots, outside the GIST folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var log = ""
        func note(_ line: String) {
            log += line + "\n"
            // folio:not-an-action debug screenshots, outside the GIST folder
            try? log.write(to: folder.appending(path: "panes.txt"), atomically: true, encoding: .utf8)
        }
        for _ in 0..<20 where workspace.currentCourses.isEmpty { try? await Task.sleep(for: .seconds(0.5)) }
        #if os(macOS)
        resize(width: SnapshotDriver.width)
        #endif
        guard let course = workspace.currentCourses.first(where: { !$0.file.notes.isEmpty && !$0.file.lectureFiles.isEmpty }) else {
            note("no course with a note and a lecture")
            return quit()
        }
        #if os(macOS)
        let second = AppLink(.material, course.file.lectureFiles[0].id)
        #else
        // A PDF pane crashes the iPad as it opens: SteadyPDFView reads PDFKit's document from a frame UIKit sets
        // before PDFView is ready.
        let second = AppLink.course(course.id, page: .materials)
        #endif
        let links: [AppLink] = [
            AppLink(.note, course.file.notes[0].id), second,
            .course(course.id, page: .quiz), .course(course.id, page: .units), .place(.today),
        ]
        let entries = links.compactMap { workspace.entry(for: $0, hint: course.id) }
        guard entries.count == links.count else {
            note("a link without a screen")
            return quit()
        }
        func shoot(_ name: String) async {
            try? await Task.sleep(for: .seconds(2.5))
            capture(folder.appending(path: "\(name).png"))
            let panes = tabs.front
            let fold = panes?.fold
            note(
                "\(name): focus \(panes?.layout.focus ?? -1), run \(fold.map { "\($0.run)" } ?? "-"), left \(fold?.left ?? []), right \(fold?.right ?? []), "
                    + "strips \(fold.map { $0.strips.sorted() } ?? [])")
        }

        tabs.open(Navigator(entries[0]))
        for entry in entries.dropFirst() { tabs.front?.openBeside(entry) }
        await shoot("1-one-bundle")
        tabs.front?.press(2)
        await shoot("2-two-bundles")
        tabs.front?.press(1)
        await shoot("3-one-pane-bundle")
        PaneBundleHook.shared.listing = true
        await shoot("4-bundle-list")
        PaneBundleHook.shared.listing = false
        try? await Task.sleep(for: .seconds(1))

        #if os(macOS)
        resize(width: 1280)
        #endif
        tabs.open(Navigator(entries[0]))
        for entry in entries[1...2] { tabs.front?.openBeside(entry) }
        tabs.front?.collapse(1)
        await shoot("5-hand-folded")
        quit()
    }

    static func quit() {
        #if os(macOS)
        NSApp.terminate(nil)
        #else
        exit(0)
        #endif
    }

    #if os(macOS)
    static func resize(width: Double) {
        guard let window = NSApp.windows.first(where: { $0.isVisible }) else { return }
        window.setContentSize(NSSize(width: width, height: SnapshotDriver.height))
        window.center()
    }

    /// The window, with an open popover's content drawn at its place on a plain backing: `cacheDisplay` draws the
    /// popover's glass as a black box with a coloured rim, and an app without screen recording access can't have the
    /// window server draw it.
    static func capture(_ url: URL) {
        let windows = NSApp.windows.filter(\.isVisible)
        guard let window = windows.first(where: { $0.sheetParent == nil && !$0.className.contains("Popover") }),
            let view = window.contentView?.superview, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds),
            let context = NSGraphicsContext(bitmapImageRep: rep)
        else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        for popover in windows where popover.className.contains("Popover") {
            guard let content = popover.contentView, let drawn = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
                continue
            }
            content.cacheDisplay(in: content.bounds, to: drawn)
            let origin = content.convert(NSPoint.zero, to: nil)
            let frame = NSRect(
                origin: NSPoint(x: popover.frame.minX + origin.x - window.frame.minX, y: popover.frame.minY + origin.y - window.frame.minY),
                size: content.bounds.size)
            let backing = NSBezierPath(roundedRect: frame, xRadius: Theme.Radius.floating, yRadius: Theme.Radius.floating)
            window.effectiveAppearance.performAsCurrentDrawingAppearance {
                let shadow = NSShadow()
                shadow.shadowBlurRadius = Theme.Space.l
                shadow.shadowOffset = NSSize(width: 0, height: -Theme.Space.xs)
                shadow.shadowColor = .black.withAlphaComponent(0.25)
                NSGraphicsContext.saveGraphicsState()
                shadow.set()
                NSColor.windowBackgroundColor.setFill()
                backing.fill()
                NSGraphicsContext.restoreGraphicsState()
                NSColor.separatorColor.setStroke()
                backing.stroke()
                drawn.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        // folio:not-an-action debug screenshots, outside the GIST folder
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
    #else
    /// The key window with what it presents (a popover is in the same window), as the screen shows it.
    static func capture(_ url: URL) {
        guard
            let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows).first(
                where: \.isKeyWindow)
        else { return }
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        // folio:not-an-action debug screenshots, outside the GIST folder
        try? image.pngData()?.write(to: url)
    }
    #endif
}

/// Opens the list of the bundle at the row's trailing end, as a click on it would.
@MainActor @Observable final class PaneBundleHook {
    static let shared = PaneBundleHook()
    var listing = false
}
#endif
