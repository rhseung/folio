import FolioDomain
import FolioMarkdown
import Foundation
import Testing

@testable import Folio

@MainActor
struct SettingsModelTests {
    @Test func nothingIsSavedBeforeTheCopyIsLoaded() throws {
        let workspace = try fixtureWorkspace()
        let model = SettingsModel(workspace: workspace)
        model.settings.study.mockMinutes = 99
        model.saveNow()
        #expect(workspace.settings.study.mockMinutes != 99)

        model.load()
        model.settings.study.mockMinutes = 99
        model.saveNow()
        #expect(workspace.settings.study.mockMinutes == 99)
    }

    @Test func backupFolderInsideGistIsRefused() throws {
        let workspace = try fixtureWorkspace()
        let model = SettingsModel(workspace: workspace)
        let gist = try #require(workspace.gist).url
        let before = model.settings.backup.folder
        model.pickBackupFolder(gist.appending(path: "backups"))
        #expect(model.settings.backup.folder == before)
        #expect(workspace.error == "백업 위치는 GIST 폴더 밖이어야 합니다.")

        let sibling = gist.deletingLastPathComponent().appending(path: gist.lastPathComponent + "-backups")
        model.pickBackupFolder(sibling)
        #expect(model.settings.backup.folder == sibling.path)
    }

    @Test func showsTheTabTheLinkNames() throws {
        let model = SettingsModel(workspace: try fixtureWorkspace(), tab: .notes)
        model.follow(.settings(.study))
        #expect(model.tab == .study)
        model.follow(.place(.settings))
        model.follow(.place(.grades))
        #expect(model.tab == .study)

        model.follow(try #require(AppLink(string: "folio://settings/letters")))
        #expect(model.tab == .record)
        model.follow(try #require(AppLink(string: "folio://settings/recording")))
        #expect(model.tab == .classes)
    }

    @Test func aTabRememberedByItsFormerNameStillOpens() {
        let saved = UserDefaults.standard.string(forKey: AppLink.SettingsPage.storageKey)
        defer { UserDefaults.standard.set(saved, forKey: AppLink.SettingsPage.storageKey) }
        for (stored, tab) in [
            ("녹음", AppLink.SettingsPage.classes), ("평어", .record), ("알림", .notifications), ("review", .study), ("없는 탭", .general),
        ] {
            UserDefaults.standard.set(stored, forKey: AppLink.SettingsPage.storageKey)
            #expect(AppLink.SettingsPage.remembered == tab)
        }
    }

    @Test func aRowWritesItsDeclaredKey() throws {
        let model = SettingsModel(workspace: try fixtureWorkspace())
        model.set(.examMinutes, .number(150))
        #expect(model.settings.schedule.examMinutes == 150)
        #expect(model.value(.examMinutes) == .number(150))
        model.set(.studyMinProblems, .number(5))
        #expect(model.settings.study.minProblems == 5)
        #expect(model.value(.studyMinProblems) == .number(5))
    }

    @Test func calloutKindsAreAddedChangedAndRemoved() throws {
        let model = SettingsModel(workspace: try fixtureWorkspace())
        model.newCallout = " Claim "
        #expect(model.canAddCallout)
        model.addCallout()
        #expect(model.newCallout.isEmpty)
        #expect(model.customCallouts.map(\.name) == ["claim"])

        model.newCallout = "theorem"
        #expect(!model.canAddCallout)
        model.newCallout = "two words"
        #expect(!model.canAddCallout)

        var theorem = try #require(model.callouts["theorem"])
        theorem.numbered = false
        model.setCallout(theorem)
        #expect(model.changed(theorem))
        theorem.numbered = true
        model.setCallout(theorem)
        #expect(!model.changed(theorem))
        #expect(model.settings.callouts?.map(\.name) == ["claim"])

        model.removeCallout("claim")
        #expect(model.settings.callouts == nil)
        #expect(model.customCallouts.isEmpty)
    }
}
