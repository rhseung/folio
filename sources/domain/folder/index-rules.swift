public enum IndexRules {
    public static let codeProjectMarkers: Set<String> = [".git", "node_modules", "__pycache__", ".venv", "build", "dist"]

    public static let maxIndexedFiles = 500

    // 루트는 0, 학기는 1, 과목은 2이다. 코드 프로젝트는 과목 아래에서만 찾는다.
    public static let courseFolderDepth = 2

    // 과목 하위 폴더(깊이 3)와 그 위는 구조이므로 크기 때문에 접지 않는다. 접으면 파일이 수천 개인 GIST 폴더
    // 전체가 항목 하나로 접힌다.
    public static let firstCollapsibleDepth = 4

    public static func isIgnoredFile(_ name: String) -> Bool {
        name == ".DS_Store" || name.hasPrefix("~$") || name.hasSuffix(".pyc")
    }

    public static func isCodeProject(childNames: some Sequence<String>) -> Bool {
        childNames.contains { codeProjectMarkers.contains($0) }
    }
}
