#if DEBUG && os(macOS)
import AppKit
import FolioDomain
import SwiftUI

@MainActor enum PaneSessionProbe {
    static let environment = ProcessInfo.processInfo.environment
    static let folder = environment["FOLIO_PANE_SESSION"].map { URL(filePath: $0, directoryHint: .isDirectory) }

    static func run(tabs: WindowTabs, workspace: Workspace, memory: PaneMemoryStore?, openTab: (AppLink) -> Void) async {
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
        if let window = NSApp.windows.first(where: { $0.isVisible }) {
            window.setContentSize(NSSize(width: SnapshotDriver.width, height: SnapshotDriver.height))
            window.center()
        }
        let classes = workspace.currentCourses.lazy.compactMap { course -> (LoadedCourse, UUID, FolioDomain.Material)? in
            let notes = Set(course.file.notes.map(\.id))
            guard
                let note = course.file.sessions.lazy.flatMap({ [$0.roughNoteId, $0.reviewNoteId].compactMap { $0 } }).first(
                    where: notes.contains),
                let lecture = course.file.lectureFiles.first(where: { $0.path.hasSuffix("05_Matchings.pdf") })
            else { return nil }
            return (course, note, lecture)
        }
        guard case let (course, noteID, lecture)? = classes.first,
            let noteEntry = workspace.entry(for: AppLink(.note, noteID), hint: course.id),
            let lectureEntry = workspace.entry(for: AppLink(.material, lecture.id, anchor: .page(6)), hint: course.id),
            let quizEntry = workspace.entry(for: .course(course.id, page: .quiz))
        else {
            note("no class with a note and a paged lecture")
            NSApp.terminate(nil)
            return
        }
        memory?.forget()
        func shoot(_ name: String) async {
            try? await Task.sleep(for: .seconds(3))
            SnapshotDriver.shared.capture(to: folder.appending(path: "\(name).png"))
            let shown = tabs.front?.navigators.map { $0.current.link.string } ?? []
            note("\(name): \(shown.joined(separator: " | "))")
        }

        tabs.open(Navigator(noteEntry))
        await shoot("1-note")
        tabs.front?.openBeside(lectureEntry)
        await shoot("2-class")
        if environment["FOLIO_PANE_SESSION_BEFORE"] != nil { memory?.forget() }
        openTab(AppLink(.note, noteID))
        await shoot("3-reopened")
        if PaneDragHook.shared.row != nil {
            for step in 1...12 {
                PaneDragHook.shared.move(by: CGFloat(step) * 16)
                try? await Task.sleep(for: .milliseconds(16))
            }
            PaneDragHook.shared.end()
        }
        await shoot("4-dragged")
        tabs.front?.openBeside(quizEntry)
        await shoot("5-narrowed")
        memory?.forget()
        NSApp.terminate(nil)
    }
}
#endif
