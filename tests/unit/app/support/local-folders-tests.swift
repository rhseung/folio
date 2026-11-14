import FolioFixtures
import Foundation
import Testing

@testable import Folio

// 테스트, 미리보기, 렌더가 이 Mac의 실제 Application Support/Folio 폴더에 닿으면, 그곳의 녹음 복구가 사용자의 끝나지 않은 강의 녹음을 옮기거나 지운다.
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
        // 시스템이 tmp를 비울 수 있으므로, 앱의 녹음은 과목에 들어가기 전까지 tmp 밖에 둔다.
        #expect(try LocalFolders.url("Recording", perGIST: true, environment: [:]).standardizedFileURL.path.hasPrefix(Self.real))
    }

    @Test func anAppRunOnAFixtureRecordsInAFolderOfItsOwn() throws {
        let fixture = ["FOLIO_GIST": "/tmp/fixture-a"]
        let recording = try LocalFolders.url("Recording", perGIST: true, environment: fixture)
        #expect(!recording.standardizedFileURL.path.hasPrefix(Self.real))
        #expect(recording == (try LocalFolders.url("Recording", perGIST: true, environment: fixture)))
        #expect(recording != (try LocalFolders.url("Recording", perGIST: true, environment: ["FOLIO_GIST": "/tmp/fixture-b"])))
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
