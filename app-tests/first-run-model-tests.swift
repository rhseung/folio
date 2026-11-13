import FolioDomain
import FolioFixtures
import FolioStorage
import Foundation
import Testing
@testable import Folio

@MainActor
struct FirstRunModelTests {
    func emptyFolder() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "first-run-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A workspace with no folder open, as on a device's first launch.
    func bareWorkspace() -> Workspace {
        let workspace = Workspace()
        workspace.pendingRecordings = PendingRecordings(url: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory))
        return workspace
    }

    @Test func theStepsRunToTheEndAndLeaveTheFirstRun() throws {
        let workspace = try fixtureWorkspace()
        workspace.showsFirstRun = true
        let model = FirstRunModel(workspace: workspace)
        model.proceed()
        #expect(model.step == .folder)
        // Opened again from settings, the folder step starts at the open folder.
        #expect(model.start == .existing)
        #expect(model.canContinue)
        model.proceed()
        #expect(model.step == .term)
        model.later()
        model.later()
        model.later()
        #expect(model.step == .claude)
        #expect(model.isLast)
        model.proceed()
        #expect(!workspace.showsFirstRun)
    }

    @Test func stepsPastTheFolderWaitForOne() {
        let model = FirstRunModel(workspace: bareWorkspace(), step: .folder)
        #expect(!model.canContinue)
        model.go(to: .claude)
        #expect(model.step == .folder)
        model.later()
        #expect(model.step == .folder)
    }

    @Test func aFreshStartOpensTheEmptyFolderAtTheTermStep() throws {
        let workspace = bareWorkspace()
        let model = FirstRunModel(workspace: workspace, step: .folder)
        let url = try emptyFolder()
        model.start = .fresh
        model.choose(url)
        #expect(model.pickedProblem == nil)
        #expect(model.pickedSummary == [String(localized: .firstRunEmptyFolder)])
        // Nothing opens until the step is left.
        #expect(workspace.gist == nil)
        model.proceed()
        #expect(workspace.gist?.url.standardizedFileURL == url.standardizedFileURL)
        #expect(model.step == .term)
        #expect(model.semester == nil)
    }

    @Test func aFolioFolderPickedFromAFreshStartOpensAsOne() throws {
        let model = FirstRunModel(workspace: bareWorkspace(), step: .folder)
        model.start = .fresh
        model.choose(try Fixture.standard.copyToTemp())
        #expect(model.start == .existing)
        #expect(model.pickedProblem == nil)
        #expect(model.canContinue)
    }

    @Test func aFolderOfOtherThingsIsRefused() throws {
        let model = FirstRunModel(workspace: bareWorkspace(), step: .folder)
        let url = try emptyFolder()
        try Data().write(to: url.appending(path: "사진.jpg"))
        model.choose(url)
        #expect(model.pickedProblem == String(localized: .firstRunProblemNotFolio))
        #expect(!model.canContinue)
    }

    @Test func theDayBoundarySavesToTheOpenFolder() throws {
        let workspace = try fixtureWorkspace()
        let model = FirstRunModel(workspace: workspace)
        model.go(to: .term)
        model.settings.settings.dayBoundaryMinutes = 5 * 60
        model.dayBoundaryChanged()
        #expect(workspace.settings.dayBoundaryMinutes == 5 * 60)
    }

    @Test func aLostFolderIsTheOnlyStepAndReconnectingItEndsTheRun() throws {
        let workspace = bareWorkspace()
        workspace.folderTrouble = .missing(path: "/nowhere/GIST")
        let model = FirstRunModel(workspace: workspace)
        #expect(model.steps == [.folder])
        #expect(!model.canGoBack)
        model.choose(try Fixture.standard.copyToTemp())
        model.proceed()
        #expect(workspace.gist != nil)
        #expect(workspace.folderTrouble == nil)
        #expect(!workspace.showsFirstRun)
    }

    @Test func anEmptyFolderInPlaceOfALostOneGoesOnToTheTerm() throws {
        let workspace = bareWorkspace()
        workspace.folderTrouble = .missing(path: "/nowhere/GIST")
        let model = FirstRunModel(workspace: workspace)
        model.choose(try emptyFolder())
        model.proceed()
        #expect(workspace.showsFirstRun)
        #expect(model.step == .term)
    }

    /// The test host is the app itself, so `UserDefaults.standard` is the real app's: a folder remembered here would
    /// have the next real launch open a fixture.
    @Test func theFirstRunNeverTouchesTheRememberedFolder() throws {
        let bookmark = UserDefaults.standard.data(forKey: Workspace.bookmarkKey)
        let path = UserDefaults.standard.string(forKey: Workspace.pathKey)
        #expect(!Workspace.remembersFolders)

        let workspace = bareWorkspace()
        let model = FirstRunModel(workspace: workspace, step: .folder)
        model.choose(try Fixture.standard.copyToTemp())
        model.proceed()
        model.go(to: .welcome)
        model.proceed()
        model.start = .fresh
        model.choose(try emptyFolder())
        model.proceed()
        #expect(workspace.gist != nil)

        #expect(UserDefaults.standard.data(forKey: Workspace.bookmarkKey) == bookmark)
        #expect(UserDefaults.standard.string(forKey: Workspace.pathKey) == path)
    }
}
