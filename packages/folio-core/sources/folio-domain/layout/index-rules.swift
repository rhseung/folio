// docs/SPEC.md "색인 제외 대상".
public enum IndexRules {
    public static let codeProjectMarkers: Set<String> = [".git", "node_modules", "__pycache__", ".venv", "build", "dist"]

    /// Folders with more files than this are not indexed until the user opts in.
    public static let maxIndexedFiles = 500

    /// Depth below the GIST root: root 0, semester 1, course 2. Code projects are only detected below courses.
    public static let courseFolderDepth = 2

    /// Course subfolders (depth 3) and everything above are structure, never collapsed for size;
    /// otherwise the whole GIST folder, with thousands of files, would collapse into one item.
    public static let firstCollapsibleDepth = 4

    public static func isIgnoredFile(_ name: String) -> Bool {
        name == ".DS_Store" || name.hasPrefix("~$") || name.hasSuffix(".pyc")
    }

    public static func isCodeProject(childNames: some Sequence<String>) -> Bool {
        childNames.contains { codeProjectMarkers.contains($0) }
    }
}
