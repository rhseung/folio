import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

enum CLI {
    @TaskLocal static var overrides: Overrides?
    @TaskLocal static var staging: Staging?

    static let appDefaults = "com.rhseung.folio"
    static let appBookmarkKey = "folio.gistBookmark"
    static let appPathKey = "folio.gistPath"

    static func gist(_ options: GlobalOptions) throws -> GISTStore {
        try gist(path: options.gist)
    }

    static func gist(path given: String?) throws -> GISTStore {
        if let s = staging { return GISTStore(url: s.folder.url) }
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
            let url = try? URL(resolvingBookmarkData: data, options: .withoutUI, bookmarkDataIsStale: &stale)
        {
            return GISTStore(url: url)
        }
        throw CLIError(
            exit: .usage, message: String(localized: .gistUnknown),
            hints: [String(localized: .gistUnknownHintOption), String(localized: .gistUnknownHintEnv)])
    }

    // Mac 앱과 같은 로그 파일에 줄을 더하지 않도록 자기 ID를 따로 둔다.
    static var device: DeviceID {
        overrides?.device ?? LocalDevice.id(in: UserDefaults(suiteName: "com.rhseung.folio.cli") ?? .standard)
    }

    static var now: Date { overrides?.now ?? .now }

    static func context(_ options: GlobalOptions) throws -> ActionContext {
        Picker.enable(options)
        return ActionContext(gist: try gist(options), device: device, now: now, dryRun: options.dryRun && staging?.writes != true)
    }
}
