#if DEBUG
import FolioDomain
import Foundation
#if os(macOS)
import AppKit
#endif

@MainActor
enum FirstRunDebug {
    private static let environment = ProcessInfo.processInfo.environment
    // `FOLIO_FIRST_RUN_STEP`은 단계 이름(`term`)이거나, 열 수 없는 기억한 폴더를 뜻하는 `missing`, `downloading`이다.
    // iPad 시뮬레이터는 화면을 밖에서 찍으므로 `SIMCTL_CHILD_FOLIO_FIRST_RUN_STEP`로 넘긴다.
    static let step = environment["FOLIO_FIRST_RUN_STEP"]
    static let walks = environment["FOLIO_SNAPSHOT_FIRST_RUN"] != nil

    nonisolated static var requested: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["FOLIO_FIRST_RUN_STEP"] != nil || env["FOLIO_SNAPSHOT_FIRST_RUN"] != nil
    }

    static let names = FirstRunStep.allCases.map(\.rawValue) + ["missing", "downloading"]

    static func show(_ name: String, in model: FirstRunModel) {
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
