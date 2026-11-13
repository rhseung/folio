#if DEBUG && os(macOS)
import AppKit
import FolioDomain
import SwiftUI

@MainActor
enum LayoutSnapshots {
    static let mode = ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_LAYOUTS"]
    static var selectedTab: CGRect?

    static func run(tabs: WindowTabs, workspace: Workspace) async {
        guard mode != nil, let directory = SnapshotDriver.directory, let window = NSApp.windows.first(where: { $0.isVisible }) else {
            return
        }
        // folio:not-an-action debug screenshots, outside the GIST folder
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        window.setContentSize(NSSize(width: SnapshotDriver.width, height: SnapshotDriver.height))
        window.center()
        for _ in 0..<20 where workspace.currentCourses.isEmpty { try? await Task.sleep(for: .seconds(0.5)) }
        let lectures = workspace.currentCourses.lazy.compactMap { course -> (UUID, SessionMaterial)? in
            course.file.sessions.lazy.compactMap(\.materials.first).first.map { (course.id, $0) }
        }
        if case let (course, lecture)? = lectures.first, let panes = tabs.front,
            let entry = workspace.entry(
                for: AppLink(.material, lecture.materialId, anchor: lecture.firstPage.map(AppLink.Anchor.page)), hint: course)
        {
            panes.focused.go(entry)
            workspace.apply(PanePreset(name: nil, slots: [.role(.lecture), .role(.quiz)], shares: [0.6, 0.4]), to: panes)
        } else {
            NSLog("layouts: no class with a lecture")
        }
        try? await Task.sleep(for: .seconds(2.5))
        shoot("layouts-window", in: directory)
        guard mode != "window" else { return NSApp.terminate(nil) }

        if let menu = tabMenu(in: window) {
            await pop(menu, at: menuPoint(in: window), in: window, step: "layouts-menu", directory: directory)
            if let layouts = menu.items.first(where: { $0.submenu != nil && $0.title == String(localized: .panesPresetsMenu) })?.submenu {
                var point = menuPoint(in: window)
                point.x += 240
                await pop(layouts, at: point, in: window, step: "layouts-submenu", directory: directory)
            }
        }
        UserDefaults.standard.set(SettingsTab.general.rawValue, forKey: SettingsTab.storageKey)
        tabs.front?.focused.go(Navigator.Entry(link: .settings(.general)))
        try? await Task.sleep(for: .seconds(2))
        shoot("layouts-settings", in: directory)
        NSApp.terminate(nil)
    }

    static func menuPoint(in window: NSWindow) -> NSPoint {
        let tab = selectedTab ?? CGRect(x: 300, y: 8, width: 200, height: 32)
        let height = window.contentView?.bounds.height ?? 0
        return NSPoint(x: tab.midX, y: height - tab.midY)
    }

    static func tabMenu(in window: NSWindow) -> NSMenu? {
        guard let content = window.contentView else { return nil }
        let point = menuPoint(in: window)
        guard
            let event = NSEvent.mouseEvent(
                with: .rightMouseDown, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
        else { return nil }
        var view = content.hitTest(content.convert(point, from: nil))
        while let v = view {
            if let menu = v.menu(for: event) { return menu }
            view = v.superview
        }
        return nil
    }

    static func pop(_ menu: NSMenu, at point: NSPoint, in window: NSWindow, step name: String, directory: URL) async {
        let started = Date()
        // 메뉴는 run loop를 자기 모드로 돌리고, 그 모드에서는 task가 실행되지 않는다. 그래서 `.common` 모드의 timer가
        // 그림을 찍고 메뉴를 닫는다.
        nonisolated(unsafe) let held = menu
        let timer = Timer(timeInterval: 0.25, repeats: true) { timer in
            guard Date().timeIntervalSince(started) > 0.8 else { return }
            timer.invalidate()
            MainActor.assumeIsolated { shoot(name, in: directory) }
            held.cancelTracking()
        }
        RunLoop.main.add(timer, forMode: .common)
        try? await Task.sleep(for: .milliseconds(100))
        let content = window.contentView
        menu.popUp(positioning: nil, at: content?.convert(point, from: nil) ?? point, in: content)
        try? await Task.sleep(for: .milliseconds(500))
    }

    static func shoot(_ name: String, in directory: URL) {
        let windows = NSApp.windows.filter(\.isVisible)
        guard
            let window = windows.filter({ !$0.className.contains("Menu") && !$0.className.contains("Glass") })
                .max(by: { $0.frame.width < $1.frame.width }),
            let view = window.contentView?.superview, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds),
            let context = NSGraphicsContext(bitmapImageRep: rep)
        else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        for menu in windows where menu.className.contains("Menu") {
            guard let content = menu.contentView, let drawn = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { continue }
            content.cacheDisplay(in: content.bounds, to: drawn)
            let frame = NSRect(
                origin: NSPoint(x: menu.frame.minX - window.frame.minX, y: menu.frame.minY - window.frame.minY),
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
        try? rep.representation(using: .png, properties: [:])?.write(to: directory.appending(path: "\(name).png"))
    }
}
#endif
