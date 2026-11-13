#if DEBUG
import FolioFixtures
import FolioStorage
import Foundation

extension Workspace {
    /// A fresh copy of the scenario with the clock pinned to its moment, for previews and offscreen renders.
    static func scenario(_ scenario: Scenario) throws -> Workspace {
        let url = try scenario.copyToTemp()
        // With FOLIO_GIST set, open() leaves the remembered folder alone, so a preview never repoints the real app or `folio`.
        setenv(environmentKey, url.path(percentEncoded: false), 1)
        let workspace = Workspace()
        workspace.pinnedNow = scenario.now
        workspace.calendar = Scenario.calendar
        // Before opening, whose reload recovers leftovers: left unset, the first use stops the run (LocalFolders).
        workspace.pendingRecordings = PendingRecordings(
            url: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory))
        workspace.open(url, remember: false)
        workspace.releaseNotes = ReleaseNotes(
            source: ReleaseList(list: ReleaseList.sample), current: ReleaseList.sample[0].version, prompts: false)
        return workspace
    }
}
#endif
