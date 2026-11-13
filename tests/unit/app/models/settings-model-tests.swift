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

    @Test func showsTheTabTheLinkNames() throws {
        let model = SettingsModel(workspace: try fixtureWorkspace(), tab: .notes)
        model.follow(.settings(.review))
        #expect(model.tab == .review)
        // A link naming no tab, or another screen's, leaves the tab as it was.
        model.follow(.place(.settings))
        model.follow(.place(.grades))
        #expect(model.tab == .review)

        // Tabs #416 merged open the tab that took them over.
        model.follow(try #require(AppLink(string: "folio://settings/letters")))
        #expect(model.tab == .record)
        model.follow(try #require(AppLink(string: "folio://settings/recording")))
        #expect(model.tab == .classes)
    }

    @Test func aTabRememberedByItsFormerNameStillOpens() {
        let saved = UserDefaults.standard.string(forKey: SettingsTab.storageKey)
        defer { UserDefaults.standard.set(saved, forKey: SettingsTab.storageKey) }
        for (stored, tab) in [
            ("녹음", SettingsTab.classes), ("평어", .record), ("알림", .notifications), ("review", .review), ("없는 탭", .general),
        ] {
            UserDefaults.standard.set(stored, forKey: SettingsTab.storageKey)
            #expect(SettingsTab.remembered == tab)
        }
    }

    @Test func reviewDaysCountFromToday() throws {
        let workspace = try fixtureWorkspace()
        let model = SettingsModel(workspace: workspace)
        model.load()
        model.settings.review.intervals = [1, 3]
        let today = workspace.today
        let days = [today.adding(days: 1), today.adding(days: 4)].map(SettingsModel.monthDay).joined(separator: " · ")
        #expect(model.reviewDays == "\(SettingsModel.monthDay(today)) → \(days)")
    }
}
