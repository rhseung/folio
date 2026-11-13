import CryptoKit
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

    /// `perGIST` folders hold data about the courses of one GIST folder. An app run on a fixture (`FOLIO_GIST`, the
    /// window snapshots included) gets them in a temporary folder of its own: fixture course IDs are fixed, so with
    /// the real folder a fixture run's leftovers would stay there forever, and the next fixture run would recover a
    /// real lecture into a throwaway folder and delete it here.
    static func url(_ name: String, perGIST: Bool = false, environment: [String: String] = ProcessInfo.processInfo.environment) throws
        -> URL
    {
        guard !isIsolated(environment) else { throw RealFolderInIsolatedRun(name: name) }
        if perGIST, let gist = environment[Workspace.environmentKey] {
            let digest = SHA256.hash(data: Data(gist.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
            return URL.temporaryDirectory.appending(path: "Folio-\(digest)/\(name)", directoryHint: .isDirectory)
        }
        return URL.applicationSupportDirectory.appending(path: "Folio/\(name)", directoryHint: .isDirectory)
    }

    static func applicationSupport(_ name: String, perGIST: Bool = false) -> URL {
        do { return try url(name, perGIST: perGIST) } catch { fatalError("\(error)") }
    }
}
