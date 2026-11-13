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
        #expect(throws: LocalFolders.RealFolderInIsolatedRun.self) {
            try LocalFolders.url("Recording", environment: ["XCODE_RUNNING_FOR_PREVIEWS": "1"])
        }
        let app = try LocalFolders.url("Recording", environment: [:])
        #expect(app.standardizedFileURL.path.hasPrefix(Self.real))
        // The app's own recordings stay out of tmp, which the system may empty before they reach their course.
        #expect(try LocalFolders.url("Recording", perGIST: true, environment: [:]).standardizedFileURL.path.hasPrefix(Self.real))
    }

    /// The window snapshots and `FOLIO_GIST` runs are the app itself, so they record, but never into this Mac's folder.
    @Test func anAppRunOnAFixtureRecordsInAFolderOfItsOwn() throws {
        let fixture = ["FOLIO_GIST": "/tmp/fixture-a"]
        let recording = try LocalFolders.url("Recording", perGIST: true, environment: fixture)
        #expect(!recording.standardizedFileURL.path.hasPrefix(Self.real))
        #expect(recording == (try LocalFolders.url("Recording", perGIST: true, environment: fixture)))
        #expect(recording != (try LocalFolders.url("Recording", perGIST: true, environment: ["FOLIO_GIST": "/tmp/fixture-b"])))
        // The Whisper model knows no courses; a fixture run shares it rather than downloading 630MB again.
        #expect(try LocalFolders.url("Whisper", environment: fixture).standardizedFileURL.path.hasPrefix(Self.real))
        #expect(throws: LocalFolders.RealFolderInIsolatedRun.self) {
            try LocalFolders.url(
                "Recording", perGIST: true, environment: fixture.merging(["XCODE_RUNNING_FOR_PREVIEWS": "1"]) { a, _ in a })
        }
    }

    @Test func fixturesAndScenariosRecordOutsideTheRealFolder() throws {
        for workspace in [try fixtureWorkspace(), try Workspace.scenario(.busyDay)] {
            #expect(!workspace.pendingRecordings.url.standardizedFileURL.path.hasPrefix(Self.real))
        }
    }
}
