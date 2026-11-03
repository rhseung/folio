import Foundation

/// This device's own folders under Application Support/Folio, the only way the app reaches them.
///
/// Tests, previews and `mise run render` share this Mac's real folders when they ask the system for them, and a run
/// on a fixture would then recover, move or delete the user's unfinished lecture recordings. In those runs asking
/// stops the process with the folder's name, so a missing override shows up at once instead of touching real files.
enum LocalFolders {
    struct RealFolderInIsolatedRun: Error, CustomStringConvertible {
        let name: String
        var description: String {
            "Application Support/Folio/\(name) is this Mac's real folder; tests, previews and renders must give their own"
        }
    }

    /// A test host (xcodebuild sets this for Swift Testing too) or an Xcode preview: never the user's own run.
    static func isIsolated(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil || environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    static func url(_ name: String, environment: [String: String] = ProcessInfo.processInfo.environment) throws -> URL {
        guard !isIsolated(environment) else { throw RealFolderInIsolatedRun(name: name) }
        return URL.applicationSupportDirectory.appending(path: "Folio/\(name)", directoryHint: .isDirectory)
    }

    static func applicationSupport(_ name: String) -> URL {
        do { return try url(name) } catch { fatalError("\(error)") }
    }
}
