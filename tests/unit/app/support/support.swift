import FolioDomain
import FolioFixtures
import FolioStorage
import Foundation

@testable import Folio

let graphTheory = UUID(uuidString: "C0000000-0000-4000-8000-000000000002")!
let fallTerm = UUID(uuidString: "5E4F1A00-0000-4000-8000-000000000003")!
let creditedTerm = UUID(uuidString: "5E4F1A00-0000-4000-8000-0000000000C1")!
let creditedCourse = UUID(uuidString: "C0000000-0000-4000-8000-0000000000C1")!

@MainActor
func fixtureWorkspace() throws -> Workspace {
    let url = try Fixture.standard.copyToTemp()
    // FOLIO_GIST가 있으면 open()이 기억한 폴더를 건드리지 않으므로, 테스트가 실제 앱이나 `folio`의 폴더를 바꾸지 않는다.
    setenv(Workspace.environmentKey, url.path(percentEncoded: false), 1)
    let workspace = Workspace()
    // 열 때 다시 읽으면서 남은 녹음을 복구하므로, 그 전에 정한다. 정하지 않으면 처음 쓸 때 테스트가 멈춘다(LocalFolders).
    workspace.pendingRecordings = PendingRecordings(
        url: URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory))
    workspace.open(url, remember: false)
    return workspace
}

@MainActor
func addCode(_ prefix: String, to workspace: Workspace) -> CourseCode.ID {
    var catalog = workspace.catalog
    let code = CourseCode(device: UUID(), at: .now, prefix: prefix)
    catalog.codes.append(code)
    workspace.saveCatalog(catalog)
    return code.id
}
