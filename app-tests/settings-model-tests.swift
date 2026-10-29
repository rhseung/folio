import FolioDomain
import Foundation
import Testing
@testable import Folio

@MainActor
struct SettingsModelTests {
    @Test func nothingIsSavedBeforeTheCopyIsLoaded() throws {
        let workspace = try fixtureWorkspace()
        let model = SettingsModel(workspace: workspace)
        model.settings.review.intervals = [99]
        model.saveNow()
        #expect(workspace.settings.review.intervals != [99])

        model.load()
        model.settings.review.intervals = [99]
        model.saveNow()
        #expect(workspace.settings.review.intervals == [99])
    }

    @Test func backupFolderInsideGistIsRefused() throws {
        let workspace = try fixtureWorkspace()
        let model = SettingsModel(workspace: workspace)
        let gist = try #require(workspace.gist).url
        let before = model.settings.backup.folder
        model.pickBackupFolder(gist.appending(path: "backups"))
        #expect(model.settings.backup.folder == before)
        #expect(workspace.error == "백업 위치는 GIST 폴더 밖이어야 합니다.")

        // A sibling whose name only starts with the GIST folder's is outside it.
        let sibling = gist.deletingLastPathComponent().appending(path: gist.lastPathComponent + "-backups")
        model.pickBackupFolder(sibling)
        #expect(model.settings.backup.folder == sibling.path)
    }

    @Test func tabLabelsKeepTheStoredNames() {
        #expect(SettingsTab.allCases.allSatisfy { $0.label == $0.rawValue })
    }
}
