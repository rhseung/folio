import FolioFixtures
import Foundation
@testable import Folio

@MainActor
func fixtureWorkspace() throws -> Workspace {
    let url = try Fixture.standard.copyToTemp()
    // With FOLIO_GIST set, open() leaves the remembered folder alone, so a test never repoints the real app or `folio`.
    setenv(Workspace.environmentKey, url.path(percentEncoded: false), 1)
    let workspace = Workspace()
    workspace.open(url, remember: false)
    return workspace
}
