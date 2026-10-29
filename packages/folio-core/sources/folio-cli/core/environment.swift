import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

struct GlobalOptions: ParsableArguments {
    @Option(help: ArgumentHelp("GIST 폴더. 없으면 FOLIO_GIST, 그다음 앱이 연 폴더", valueName: "path"))
    var gist: String?

    @Flag(help: "결과를 JSON 하나로 출력")
    var json = false

    @Flag(help: "쓰지 않고 바뀔 것만 보여 주기")
    var dryRun = false

    @Flag(name: [.customShort("y"), .long], help: "확인 없이 실행. 이동과 삭제는 사용자 승인 뒤에만")
    var yes = false

    @Flag(help: "항목을 fzf로 고르지 않기")
    var noPick = false
}

/// What tests pin down so the CLI and a direct action leave the same files.
struct Overrides: Sendable {
    var gist: URL
    var device: DeviceID
    var now: Date
    var gradesUnlocked = true
}

enum CLI {
    @TaskLocal static var overrides: Overrides?

    /// The app keeps its folder as a bookmark in its own defaults (`Workspace.bookmarkKey`).
    static let appDefaults = "com.rhseung.folio"
    static let appBookmarkKey = "folio.gistBookmark"
    /// Written by the app beside the bookmark (`Workspace.pathKey`); the bookmark stays as the fallback for an app that hasn't yet.
    static let appPathKey = "folio.gistPath"

    static func gist(_ options: GlobalOptions) throws -> GISTStore {
        try gist(path: options.gist)
    }

    static func gist(path given: String?) throws -> GISTStore {
        if let o = overrides { return GISTStore(url: o.gist) }
        if let path = given ?? ProcessInfo.processInfo.environment["FOLIO_GIST"] {
            return GISTStore(url: URL(filePath: (path as NSString).expandingTildeInPath, directoryHint: .isDirectory))
        }
        let app = UserDefaults(suiteName: appDefaults)
        if let path = app?.string(forKey: appPathKey), FileManager.default.fileExists(atPath: path) {
            return GISTStore(url: URL(filePath: path, directoryHint: .isDirectory))
        }
        var stale = false
        if let data = app?.data(forKey: appBookmarkKey),
           let url = try? URL(resolvingBookmarkData: data, options: .withoutUI, bookmarkDataIsStale: &stale) {
            return GISTStore(url: url)
        }
        throw CLIError(exit: .usage, message: "GIST 폴더를 모릅니다", hints: ["folio --gist <경로> …", "export FOLIO_GIST=<경로>"])
    }

    /// Its own ID, apart from the Mac app's, so the two never append to the same log file (docs/SPEC.md "쓰기와 안전").
    static var device: DeviceID {
        overrides?.device ?? LocalDevice.id(in: UserDefaults(suiteName: "com.rhseung.folio.cli") ?? .standard)
    }

    static var now: Date { overrides?.now ?? .now }

    static func context(_ options: GlobalOptions) throws -> ActionContext {
        Picker.enable(options)
        return ActionContext(gist: try gist(options), device: device, now: now, dryRun: options.dryRun)
    }
}
