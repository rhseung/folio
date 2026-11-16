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

    static let tests = "tests"
    static let lintTests = "tests/unit/tools/lint"
    static let appTests = "tests/unit/app"
    static let appE2E = "tests/e2e/app"
    static let localFoldersTests = "tests/unit/app/support/local-folders-tests.swift"
}
