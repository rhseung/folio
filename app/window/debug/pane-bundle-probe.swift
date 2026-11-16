#if DEBUG
import FolioDomain
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

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
        // PDF 칸을 열면 iPad 앱이 비정상 종료된다. `SteadyPDFView`가 `PDFView`가 준비되기 전에 UIKit이 정한 frame에서
        // PDFKit의 문서를 읽기 때문이다.
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

    // `cacheDisplay`는 popover의 glass를 테두리 있는 검은 상자로 그리고, 화면 기록 권한이 없는 앱은 window server에
    // 그려 달라고 할 수 없다. 그래서 popover의 내용을 단색 배경 위에 직접 그린다.
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
#endif
