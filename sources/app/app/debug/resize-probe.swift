#if os(macOS) && (DEBUG || RESIZE_PROBE)
import AppKit
import FolioDomain
import QuartzCore
import SwiftUI

@MainActor final class ResizeProbe: NSObject {
    static let environment = ProcessInfo.processInfo.environment
    static let file = environment["FOLIO_RESIZE_PROBE"].map { URL(filePath: $0) }
    static var marked: [String: NSHashTable<NSView>] = [:]
    static let leading = ["sidebar", "back", "firstTab"]

    private struct Frame {
        var width: CGFloat
        var interval: CFTimeInterval
        var setFrame: CFTimeInterval
        var moved: [String: CGFloat]
        var overflowed: Bool
        var overlapped: Bool
        var at: [String: (x: CGFloat, count: Int)]
    }

    private let window: NSWindow
    private let least: CGFloat
    private let most: CGFloat
    private let legs: Int
    private var link: CADisplayLink?
    private var frames: [Frame] = []
    private var last: (time: CFTimeInterval, width: CGFloat, setFrame: CFTimeInterval)?
    private var rest: [String: CGFloat] = [:]
    private var width: CGFloat
    private var step: CGFloat = -12
    private var leg = 0
    private var frame = 0
    private var done: CheckedContinuation<Void, Never>?
    private var drag: (rest: CGFloat, least: CGFloat, most: CGFloat)?
    private weak var divider: NSView?
    private var note = ""

    private init(window: NSWindow, least: CGFloat, most: CGFloat, legs: Int) {
        self.window = window
        self.least = least
        self.most = most
        self.legs = legs
        width = most
    }

    static func run(
        window: () -> NSWindow?, workspace: Workspace, openTab: ((AppLink, UUID) -> Void)?, front: (Int) -> Void,
        openBeside: (AppLink, UUID) -> Void, frontPanes: () -> TabPanes?
    ) async {
        guard let file else { return }
        try? await Task.sleep(for: .seconds(4))
        guard let window = window() ?? NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) else { return }
        if let folder = environment["FOLIO_RESIZE_RECORD"] {
            await record(
                in: folder, window: window, workspace: workspace, openTab: openTab, front: front, openBeside: openBeside,
                frontPanes: frontPanes)
            // folio:not-an-action debug measurements, outside the GIST folder
            try? "done\n".write(to: file, atomically: true, encoding: .utf8)
            return NSApp.terminate(nil)
        }
        let count = environment["FOLIO_RESIZE_TABS"].flatMap(Int.init) ?? 6
        let courses = workspace.currentCourses
        let notes = courses.flatMap { c in c.file.notes.map { (AppLink(.note, $0.id), c.id) } }
        let pages = courses.map { (AppLink.course($0.id), $0.id) }
        var links: [(AppLink, UUID)] = []
        for i in 0..<max(notes.count, pages.count) {
            if i < notes.count { links.append(notes[i]) }
            if i < pages.count { links.append(pages[i]) }
        }
        if let openTab, !links.isEmpty {
            for i in 0..<count {
                let (link, course) = links[i % links.count]
                openTab(link, course)
                try? await Task.sleep(for: .seconds(2))
            }
        }
        let number =
            switch environment["FOLIO_RESIZE_FRONT"] {
            case "today": 1
            case "course": 3
            default: 2
            }
        let panes = environment["FOLIO_RESIZE_PANES"].flatMap(Int.init) ?? 1
        if let beside = environment["FOLIO_RESIZE_BESIDE"], let course = courses.first {
            let session = course.file.sessions.first { $0.roughNoteId != nil && !$0.materials.isEmpty } ?? course.file.sessions.first
            let links: [AppLink?] = beside.split(separator: ",").map { kind in
                switch kind {
                case "pdf": course.file.materials.first { $0.path.lowercased().hasSuffix(".pdf") }.map { AppLink(.material, $0.id) }
                case "quiz": AppLink.course(course.id, page: .quiz)
                case "session": session.map { AppLink(.session, $0.id) }
                case "note": course.file.notes.first.map { AppLink(.note, $0.id) }
                case "overview": AppLink.course(course.id)
                default: nil
                }
            }
            front(number)
            for link in links.compactMap({ $0 }) {
                openBeside(link, course.id)
                try? await Task.sleep(for: .seconds(2))
            }
        } else if panes > 1, let course = courses.first {
            let lecture = course.file.materials.first { $0.path.lowercased().hasSuffix(".pdf") }.map { AppLink(.material, $0.id) }
            let besides = [lecture, AppLink.course(course.id, page: .quiz)].compactMap { $0 }
            for tab in Set([number, 3]).sorted() where tab <= count + 1 {
                front(tab)
                for link in besides.prefix(panes - 1) {
                    openBeside(link, course.id)
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        }
        front(number)
        try? await Task.sleep(for: .seconds(3))
        let screen = window.screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let least = max(window.minSize.width, window.frameRect(forContentRect: NSRect(origin: .zero, size: window.contentMinSize)).width)
        let wide = environment["FOLIO_RESIZE_WIDTH"].flatMap(Double.init).map { min(CGFloat($0), screen.width) } ?? screen.width
        window.setFrame(NSRect(x: screen.minX, y: screen.minY, width: wide, height: min(900, screen.height)), display: true)
        try? await Task.sleep(for: .seconds(2))
        let probe = ResizeProbe(
            window: window, least: least, most: screen.width, legs: environment["FOLIO_RESIZE_LEGS"].flatMap(Int.init) ?? 4)
        for name in leading { probe.rest[name] = probe.x(of: name) }
        if let act = environment["FOLIO_RESIZE_ACT"], let folder = environment["FOLIO_RESIZE_SHOTS"] {
            if probe.grab() { await probe.act(act, folder: folder) }
            // folio:not-an-action debug measurements, outside the GIST folder
            try? probe.note.write(to: file, atomically: true, encoding: .utf8)
            return NSApp.terminate(nil)
        }
        if environment["FOLIO_RESIZE_DRAG"] == "1" {
            guard probe.grab() else {
                // folio:not-an-action debug measurements, outside the GIST folder
                try? "no divider to drag: \(probe.note)\n".write(to: file, atomically: true, encoding: .utf8)
                return NSApp.terminate(nil)
            }
        }
        await probe.drive()
        // folio:not-an-action debug measurements, outside the GIST folder
        try? probe.table().write(to: file, atomically: true, encoding: .utf8)
        // folio:not-an-action the same, frame by frame
        try? probe.trace().write(to: file.appendingPathExtension("frames"), atomically: true, encoding: .utf8)
        try? await Task.sleep(for: .seconds(1))
        NSApp.terminate(nil)
    }

    private func x(of name: String) -> CGFloat? {
        Self.marked[name]?.allObjects.first { $0.window === window && !$0.isHiddenOrHasHiddenAncestor }.map {
            $0.convert(NSPoint.zero, to: nil).x
        }
    }

    private func end(of name: String) -> CGFloat? {
        Self.marked[name]?.allObjects.first { $0.window === window && !$0.isHiddenOrHasHiddenAncestor }.map {
            $0.convert(NSPoint(x: $0.bounds.maxX, y: 0), to: nil).x
        }
    }

    private func drive() async {
        await withCheckedContinuation { continuation in
            done = continuation
            let link = window.displayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        if let last { shoot(last.width) }
        let now = CACurrentMediaTime()
        if let last {
            var moved: [String: CGFloat] = [:]
            for name in Self.leading {
                if let x = x(of: name), let at = rest[name] { moved[name] = x - at }
            }
            let overflowed = x(of: "trailing").map { $0 >= window.frame.width } ?? true
            let overlapped = x(of: "trailing").flatMap { trailing in end(of: "newTab").map { $0 > trailing + 0.5 } } ?? false
            var at: [String: (x: CGFloat, count: Int)] = [:]
            for name in Self.leading + ["trailing", "divider"] {
                let views = Self.marked[name]?.allObjects.filter { $0.window === window && !$0.isHiddenOrHasHiddenAncestor } ?? []
                at[name] = (views.first.map { $0.convert(NSPoint.zero, to: nil).x } ?? -1, views.count)
            }
            at["newTabEnd"] = (end(of: "newTab") ?? -1, 1)
            if let divider { at["divider"] = (divider.convert(NSPoint.zero, to: nil).x, 1) }
            frames.append(
                Frame(
                    width: last.width, interval: now - last.time, setFrame: last.setFrame, moved: moved, overflowed: overflowed,
                    overlapped: overlapped, at: at))
        }
        if leg >= legs {
            link.invalidate()
            done?.resume()
            done = nil
            return
        }
        let (least, most) = drag.map { ($0.least, $0.most) } ?? (least, most)
        width += step
        if width <= least || width >= most {
            width = min(max(width, least), most)
            step = -step
            leg += 1
        }
        let begin = CACurrentMediaTime()
        if let drag {
            if leg >= legs { PaneDragHook.shared.end() } else { PaneDragHook.shared.move(by: width - drag.rest) }
        } else {
            window.setFrame(NSRect(x: window.frame.minX, y: window.frame.minY, width: width, height: window.frame.height), display: true)
        }
        last = (now, width, CACurrentMediaTime() - begin)
    }

    private func grab() -> Bool {
        let dividers = Self.marked["divider"]?.allObjects.filter { $0.window === window && !$0.isHiddenOrHasHiddenAncestor } ?? []
        note =
            "active=\(NSApp.isActive) visible=\(window.occlusionState.contains(.visible)) dividers at "
            + dividers.map { String(format: "%.0f", $0.convert(NSPoint.zero, to: nil).x) }.joined(separator: ",")
        guard dividers.count == 1, PaneDragHook.shared.row != nil, let divider = dividers.first else { return false }
        self.divider = divider
        let mid = divider.convert(NSPoint(x: divider.bounds.midX, y: divider.bounds.midY), to: nil)
        let span = Self.environment["FOLIO_RESIZE_SPAN"].flatMap(Double.init).map { CGFloat($0) } ?? 300
        drag = (mid.x, mid.x - span, mid.x + span)
        width = mid.x
        step = -8
        rest["divider"] = x(of: "divider")
        return true
    }

    private func act(_ act: String, folder: String) async {
        guard let row = PaneDragHook.shared.row, let drag else { return }
        PaneDragHook.shared.move(by: drag.least - drag.rest)
        PaneDragHook.shared.end()
        try? await Task.sleep(for: .seconds(2))
        if act == "unfold" || act == "strip-menu" {
            row.panes.collapse(1)
            try? await Task.sleep(for: .seconds(2))
        }
        if act.hasSuffix("menu"), let content = window.contentView {
            let point: NSPoint
            if act == "menu" {
                guard let tab = Self.marked["firstTab"]?.allObjects.first(where: { $0.window === window }) else { return }
                point = tab.convert(NSPoint(x: tab.bounds.maxX - 48, y: tab.bounds.midY), to: nil)
            } else {
                point = content.convert(
                    NSPoint(x: content.bounds.maxX - Theme.Size.panelInset - Theme.Size.paneStrip / 2, y: content.bounds.midY), to: nil)
            }
            return menu(at: point)
        }
        capture("\(folder)/\(act)-0000.png")
        let start = CACurrentMediaTime()
        switch act {
        case "even": row.panes.even()
        case "collapse": row.panes.collapse(1)
        default: row.panes.press(1)
        }
        while CACurrentMediaTime() - start < 0.8 {
            try? await Task.sleep(for: .milliseconds(16))
            capture("\(folder)/\(act)-\(String(format: "%04d", Int((CACurrentMediaTime() - start) * 1000))).png")
        }
        try? await Task.sleep(for: .seconds(1))
        capture("\(folder)/\(act)-rest.png")
    }

    private static func record(
        in folder: String, window: NSWindow, workspace: Workspace, openTab: ((AppLink, UUID) -> Void)?,
        front: (Int) -> Void, openBeside: (AppLink, UUID) -> Void, frontPanes: () -> TabPanes?
    ) async {
        let courses = workspace.currentCourses
        guard
            let course = environment["FOLIO_RESIZE_COURSE"].flatMap({ name in courses.first { $0.title.contains(name) } }) ?? courses.first
        else { return }
        let screen = window.screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let wide = environment["FOLIO_RESIZE_WIDTH"].flatMap(Double.init).map { min(CGFloat($0), screen.width) } ?? screen.width
        let high =
            environment["FOLIO_RESIZE_HEIGHT"].flatMap(Double.init).map { min(CGFloat($0), screen.height) } ?? min(900, screen.height)
        window.setFrame(NSRect(x: screen.minX, y: screen.maxY - high, width: wide, height: high), display: true)
        let page = AppLink.course(course.id, page: environment["FOLIO_RESIZE_PAGE"].flatMap(AppLink.CoursePage.init(rawValue:)))
        if environment["FOLIO_RESIZE_BESIDE"] == "overview" {
            front(1)
            openBeside(page, course.id)
        } else {
            openTab?(page, course.id)
        }
        try? await Task.sleep(for: .seconds(environment["FOLIO_RESIZE_SETTLE"].flatMap(Double.init) ?? 6))
        let fm = FileManager.default
        // folio:not-an-action debug measurements, outside the GIST folder
        try? "window \(window.frame) panes \(frontPanes()?.count ?? 0) column \(frontPanes()?.focusedTrail.column != nil)\n".write(
            toFile: "\(folder)/setup.txt", atomically: true, encoding: .utf8)
        // folio:not-an-action debug handshake with the recorder, outside the GIST folder
        fm.createFile(atPath: "\(folder)/ready", contents: nil)
        for _ in 0..<200 where !fm.fileExists(atPath: "\(folder)/recording") { try? await Task.sleep(for: .milliseconds(50)) }
        try? await Task.sleep(for: .milliseconds(500))
        for step in (environment["FOLIO_RESIZE_ACT"] ?? "column").split(separator: ",") {
            let panes = frontPanes()
            switch step {
            case "column": panes?.focusedTrail.column?.toggle()
            case "even": panes?.even()
            case "wide":
                if let row = PaneDragHook.shared.row {
                    row.dragged(0, by: -CGFloat(environment["FOLIO_RESIZE_SPAN"].flatMap(Double.init) ?? 300), folded: row.folded)
                    row.dropped()
                }
            case "tab": openTab?(page, course.id)
            default: break
            }
            try? await Task.sleep(for: .milliseconds(1500))
        }
        try? await Task.sleep(for: .seconds(3))
    }

    private func menu(at point: NSPoint) {
        guard
            let event = NSEvent.mouseEvent(
                with: .rightMouseDown, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1),
            let frame = window.contentView?.superview
        else { return }
        var view = frame.hitTest(frame.convert(point, from: nil))
        while let v = view, v.menu(for: event) == nil { view = v.superview }
        guard let view, let menu = view.menu(for: event) else { return note += " no menu" }
        note += " menu \(menu.items.map(\.title))"
        // 메뉴는 자기 run loop 모드에서 동작하고, 그동안 main queue는 기다린다. 그래서 run loop의 common 모드에서 실행한다.
        nonisolated(unsafe) let held = menu
        let close = Timer(timeInterval: 6, repeats: false) { _ in MainActor.assumeIsolated { held.cancelTracking() } }
        RunLoop.main.add(close, forMode: .common)
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    private func shoot(_ shown: CGFloat) {
        guard leg == 0, let folder = Self.environment["FOLIO_RESIZE_SHOTS"] else { return }
        frame += 1
        guard frame % 3 == 1 else { return }
        capture("\(folder)/\(String(format: "%03d", frame))-\(Int(shown)).png")
    }

    private func capture(_ path: String) {
        let capture = Process()
        capture.executableURL = URL(filePath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l\(window.windowNumber)", path]
        try? capture.run()
        while capture.isRunning { usleep(2000) }
        guard !FileManager.default.fileExists(atPath: path), let view = window.contentView?.superview,
            let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        // folio:not-an-action debug measurements, outside the GIST folder
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(filePath: path))
    }

    private func trace() -> String {
        frames.map { f in
            "\(Int(f.width))\t"
                + (Self.leading + ["trailing", "newTabEnd", "divider"]).map { n in
                    f.at[n].map { "\(n)=\(String(format: "%.1f", $0.x))x\($0.count)" } ?? "\(n)=-"
                }.joined(separator: "\t")
        }.joined(separator: "\n")
    }

    private func table() -> String {
        let refresh = 1.0 / Double(window.screen?.maximumFramesPerSecond ?? 60)
        func ms(_ s: Double) -> String { String(format: "%.1f", s * 1000) }
        func pct(_ values: [Double], _ p: Double) -> Double {
            let sorted = values.sorted()
            return sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))]
        }
        func line(_ name: String, _ frames: [Frame]) -> String {
            let intervals = frames.map(\.interval)
            let total = intervals.reduce(0, +)
            let hitch = intervals.reduce(0) { $0 + max(0, $1 - refresh * 1.5) } / max(total, 1e-9)
            var out =
                "\(name)\tframes=\(frames.count)\tfps=\(String(format: "%.1f", Double(frames.count) / max(total, 1e-9)))"
                + "\tp50=\(ms(pct(intervals, 0.5)))\tp95=\(ms(pct(intervals, 0.95)))\thitch_ms_per_s=\(ms(hitch))"
                + "\tsetFrame_p50=\(ms(pct(frames.map(\.setFrame), 0.5)))\toverflow_frames=\(frames.filter(\.overflowed).count)"
                + "\toverlap_frames=\(frames.filter(\.overlapped).count)"
            for item in Self.leading {
                let moved = frames.compactMap { $0.moved[item] }.map(abs)
                out += "\t\(item)_moved=\(moved.filter { $0 > 0.5 }.count)/\(moved.count) max=\(String(format: "%.0f", moved.max() ?? 0))"
            }
            return out
        }
        let rests = Self.leading.map { "\($0)=\(rest[$0].map { String(format: "%.0f", $0) } ?? "-")" }.joined(separator: " ")
        var out = "refresh=\(Int(1 / refresh))Hz least=\(Int(least)) most=\(Int(most)) rest: \(rests) \(note)\n"
        out += line("all", frames) + "\n"
        let band: CGFloat = 200
        var start = (least / band).rounded(.down) * band
        while start < most {
            let inBand = frames.filter { $0.width >= start && $0.width < start + band }
            if !inBand.isEmpty { out += line("\(Int(start))-\(Int(start + band - 1))", inBand) + "\n" }
            start += band
        }
        return out
    }
}
#endif
