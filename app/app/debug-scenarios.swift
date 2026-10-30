#if DEBUG
import FolioFixtures
import Foundation

extension Workspace {
    /// A fresh copy of the scenario with the clock pinned to its moment, for previews and offscreen renders.
    static func scenario(_ scenario: Scenario) throws -> Workspace {
        let url = try scenario.copyToTemp()
        // With FOLIO_GIST set, open() leaves the remembered folder alone, so a preview never repoints the real app or `folio`.
        setenv(environmentKey, url.path(percentEncoded: false), 1)
        let workspace = Workspace()
        workspace.pinnedNow = scenario.now
        workspace.open(url, remember: false)
        return workspace
    }
}
#endif
