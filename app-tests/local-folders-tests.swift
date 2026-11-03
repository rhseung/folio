import FolioFixtures
import Foundation
import Testing
@testable import Folio

/// Tests, previews and renders must never reach this Mac's real Application Support/Folio folders: recovery there
/// would move or delete the user's unfinished lecture recordings.
@MainActor
struct LocalFoldersTests {
    static let real = URL.applicationSupportDirectory.appending(path: "Folio", directoryHint: .isDirectory).standardizedFileURL.path

    @Test func aTestHostIsRefusedTheRealFolders() {
        #expect(LocalFolders.isIsolated())
        #expect(throws: LocalFolders.RealFolderInIsolatedRun.self) { try LocalFolders.url("Recording") }
        #expect(throws: LocalFolders.RealFolderInIsolatedRun.self) { try LocalFolders.url("Whisper") }
    }

    @Test func aPreviewIsRefusedAndTheAppIsNot() throws {
        #expect(throws: LocalFolders.RealFolderInIsolatedRun.self) { try LocalFolders.url("Recording", environment: ["XCODE_RUNNING_FOR_PREVIEWS": "1"]) }
        let app = try LocalFolders.url("Recording", environment: [:])
        #expect(app.standardizedFileURL.path.hasPrefix(Self.real))
    }

    @Test func fixturesAndScenariosRecordOutsideTheRealFolder() throws {
        for workspace in [try fixtureWorkspace(), try Workspace.scenario(.busyDay)] {
            #expect(!workspace.pendingRecordings.url.standardizedFileURL.path.hasPrefix(Self.real))
        }
    }
}
