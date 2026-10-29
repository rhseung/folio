import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

struct GlobalOptions: ParsableArguments {
    @Option(help: ArgumentHelp(String(localized: .globalOptionsHelpGist), valueName: "path"))
    var gist: String?

    @Flag(help: ArgumentHelp(String(localized: .globalOptionsHelpJson)))
    var json = false

    @Flag(help: ArgumentHelp(String(localized: .globalOptionsHelpDryRun)))
    var dryRun = false

    @Flag(name: [.customShort("y"), .long], help: ArgumentHelp(String(localized: .globalOptionsHelpYes)))
    var yes = false

    @Flag(help: ArgumentHelp(String(localized: .globalOptionsHelpNoPick)))
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
        throw CLIError(exit: .usage, message: String(localized: .gistUnknown), hints: [String(localized: .gistUnknownHintOption), String(localized: .gistUnknownHintEnv)])
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
