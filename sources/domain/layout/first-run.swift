public enum FirstRunStep: String, CaseIterable, Sendable, Hashable, Comparable {
    case welcome, folder, term, profile, permissions, claude

    public var isOptional: Bool { self > .folder }

    public var next: FirstRunStep? { Self.allCases.firstIndex(of: self).flatMap { Self.allCases.dropFirst($0 + 1).first } }
    public var previous: FirstRunStep? { Self.allCases.firstIndex(of: self).flatMap { $0 > 0 ? Self.allCases[$0 - 1] : nil } }

    public func isReachable(folderOpen: Bool) -> Bool { self <= .folder || folderOpen }

    public static func < (a: Self, b: Self) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }
}

public enum FolderStart: String, CaseIterable, Sendable, Hashable {
    case fresh, existing
}

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

public enum FolderChoiceProblem: Hashable, Sendable {
    case alreadyFolio, notEmpty, empty, notFolio
}

// 앱이 열 때 읽는 파일(transcript, settings, catalog, 모든 course.json)이 이 기기에 있어야 한다. 아직 내려받지
// 않은 iCloud 폴더의 파일은 자리표시자라서, 읽으면 실제 학기 대신 빈 학기를 보인다.
public enum FolderAvailability: Hashable, Sendable {
    case ready
    case missing
    case downloading(done: Int, total: Int)

    public init(exists: Bool, downloaded: [Bool]) {
        guard exists else { self = .missing; return }
        let done = downloaded.count { $0 }
        self = done == downloaded.count ? .ready : .downloading(done: done, total: downloaded.count)
    }

    public var fraction: Double {
        switch self {
        case .ready: 1
        case .missing: 0
        case .downloading(let done, let total): total == 0 ? 1 : Double(done) / Double(total)
        }
    }
}
