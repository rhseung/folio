// 규칙이 보는 저장소 경로는 이 표에만 적는다. 폴더를 옮기면 규칙마다 찾아 고치지 않고 이 표만 고친다.
enum RepoPath {
    // Codebase가 Swift 파일을 읽는 최상위 폴더다.
    static let roots = [app, packages, tests]

    static let app = "app"
    static let features = "app/features"
    static let design = "app/design"
    static let platform = "app/platform"
    static let appDebug = "app/window/debug"
    static let theme = "app/design/tokens/theme.swift"
    static let localFolders = "app/workspace/services/local-folders.swift"

    static let packages = "sources"
    static let actions = "sources/actions"
    static let fixtures = "sources/fixtures"
    // folio-lint는 자기가 찾는 이름과 경로를 코드에 적으므로 그런 이름을 찾는 규칙에서 뺀다.
    static let lint = "sources/tools/lint"
    static let diskFree = ["sources/core", "sources/domain", "sources/markdown"]
    // standard-layout.swift를 타입마다 나눈 파일들이다. 표준 구조의 이름은 이 파일들에만 적는다.
    static let standardLayout: Set = [
        "sources/domain/folder/standard-layout.swift", "sources/domain/folder/term.swift",
        "sources/domain/folder/semester-folder.swift", "sources/domain/folder/course-folder.swift",
        "sources/domain/folder/assignment-kind.swift",
    ]
    static let launchFiles: Set = [
        "app/folio-app.swift", localFolders, "app/workspace/workspace.swift", "sources/cli/environment/cli.swift",
    ]

    // 학업을 다루는 모듈에서 바로 아래 폴더를 영역(`Area`)으로 나누는 층이다. tests/unit은 sources의 층을 같은 경로로 따른다.
    static let areaLayers = [
        "sources/domain", "sources/storage", actions, "sources/cli/commands", "sources/cli/generated", features, platform,
    ]
    // 영역 층에 있지만 영역이 아니라 그 층의 바탕을 담는 폴더다. `actions/query`는 모든 읽기의 바탕이다.
    static let layerBases: Set = ["query", generated]
    // 도구가 쓰는 폴더라서 무게와 이름을 보지 않는다.
    static let generated = "generated"
    // 이 폴더들의 바로 아래 폴더는 모듈(또는 그 테스트) 하나다. 모듈 폴더는 Package.swift와 project.yml이 정하므로 무게와
    // 이름을 보지 않는다.
    static let moduleParents: Set = [packages, "sources/tools", unitTests, "tests/unit/tools", "tests/e2e"]

    static let tests = "tests"
    static let unitTests = "tests/unit"
    static let lintTests = "tests/unit/tools/lint"
    static let appTests = "tests/unit/app"
    static let appE2E = "tests/e2e/app"
    static let localFoldersTests = "tests/unit/app/support/local-folders-tests.swift"
}
