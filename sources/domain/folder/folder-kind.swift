// 첫 화면에서 iCloud 트리 전체를 훑지 않도록 위 두 단계만 읽는다. GIST 폴더인지 가리는 데는 이것으로 충분하다.
public enum FolderKind: Hashable, Sendable {
    case empty
    case gist(semesters: Int, courses: Int)
    case other

    public init(_ tree: FolderTree) {
        // `.folio`가 아닌 숨은 파일(.DS_Store, Icon\r, 동기화 표시 파일)은 시스템의 파일이고 학생의 파일이 아니다.
        let children = tree.children.filter { $0.name == StandardLayout.metadataFolder || !$0.name.hasPrefix(".") }
        guard !children.isEmpty else { self = .empty; return }
        let semesters = children.filter { !$0.isFile && SemesterFolder(name: $0.name) != nil }
        let marked =
            !semesters.isEmpty
            || children.contains {
                !$0.isFile && ($0.name == StandardLayout.metadataFolder || $0.name == StandardLayout.creditedFolder)
            }
        guard marked else { self = .other; return }
        let sources = children.filter { !$0.isFile && $0.name == StandardLayout.creditedFolder }.flatMap(\.children)
        let courses = (semesters + sources).filter { !$0.isFile }.flatMap(\.children)
            .filter { !$0.isFile && StandardLayout.isCourseFolderName($0.name) }
        self = .gist(semesters: semesters.count, courses: courses.count)
    }

    public var start: FolderStart? {
        switch self {
        case .empty: .fresh
        case .gist: .existing
        case .other: nil
        }
    }

    public func problem(for start: FolderStart) -> FolderChoiceProblem? {
        switch (start, self) {
        case (.fresh, .empty), (.existing, .gist): nil
        case (.fresh, .gist): .alreadyFolio
        case (.fresh, .other): .notEmpty
        case (.existing, .empty): .empty
        case (.existing, .other): .notFolio
        }
    }
}
