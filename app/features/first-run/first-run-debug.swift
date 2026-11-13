#if DEBUG
import FolioDomain
import Foundation
#if os(macOS)
import AppKit
#endif

/// Debug-only ways to see the first run on a folder that is already open (a fixture's, `FOLIO_GIST`), whose steps
/// would otherwise never show.
@MainActor
enum FirstRunDebug {
    private static let environment = ProcessInfo.processInfo.environment
    /// `FOLIO_FIRST_RUN_STEP`: a step's name (`term`), or `missing` or `downloading` for a remembered folder that can't
    /// be opened. For the iPad simulator, whose screen is captured from outside (`SIMCTL_CHILD_FOLIO_FIRST_RUN_STEP`).
    static let step = environment["FOLIO_FIRST_RUN_STEP"]
    /// `FOLIO_SNAPSHOT_FIRST_RUN` with `FOLIO_SNAPSHOT_DIR`, on the Mac: every step in turn drawn into
    /// `first-run-<step>.png`, then the app quits.
    static let walks = environment["FOLIO_SNAPSHOT_FIRST_RUN"] != nil

    nonisolated static var requested: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["FOLIO_FIRST_RUN_STEP"] != nil || env["FOLIO_SNAPSHOT_FIRST_RUN"] != nil
    }

    static let names = FirstRunStep.allCases.map(\.rawValue) + ["missing", "downloading"]

    static func show(_ name: String, in model: FirstRunModel) {
        // A made-up place: the picture shows how a path reads, not this Mac's folders.
        let place = "~/Library/Mobile Documents/com~apple~CloudDocs/GIST"
        switch name {
        case "missing": model.debugTrouble = .missing(path: place)
        case "downloading": model.debugTrouble = .downloading(path: place, done: 1204, total: 4812)
        default:
            model.debugTrouble = nil
            if let step = FirstRunStep(rawValue: name) { model.step = step }
        }
    }

    static func run(_ model: FirstRunModel) async {
        if let step { show(step, in: model) }
        #if os(macOS)
        guard walks, let directory = SnapshotDriver.directory else { return }
        // folio:not-an-action debug screenshots, outside the GIST folder
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let window = NSApp.windows.first(where: { $0.isVisible }) {
            window.setContentSize(NSSize(width: SnapshotDriver.width, height: SnapshotDriver.height))
            window.center()
        }
        for name in names {
            show(name, in: model)
            try? await Task.sleep(for: .seconds(1.5))
            SnapshotDriver.shared.capture(to: directory.appending(path: "first-run-\(name).png"))
        }
        NSApp.terminate(nil)
        #endif
    }
}
#endif
