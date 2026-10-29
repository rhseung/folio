import FolioFixtures
import Foundation
@testable import Folio

/// IDs from `Fixture.standard`. 그래프 이론 starts with no sessions, units or class times.
let graphTheory = UUID(uuidString: "C0000000-0000-4000-8000-000000000002")!
let fallTerm = UUID(uuidString: "5E4F1A00-0000-4000-8000-000000000003")!

@MainActor
func fixtureWorkspace() throws -> Workspace {
    let url = try Fixture.standard.copyToTemp()
    // With FOLIO_GIST set, open() leaves the remembered folder alone, so a test never repoints the real app or `folio`.
    setenv(Workspace.environmentKey, url.path(percentEncoded: false), 1)
    let workspace = Workspace()
    workspace.open(url, remember: false)
    return workspace
}
