/// The first run's steps (#453, 안 B). Only the folder can't be put off: every later step writes into it.
public enum FirstRunStep: String, CaseIterable, Sendable, Hashable, Comparable {
    case welcome, folder, term, profile, permissions, claude

    /// Steps that can be put off with "나중에" and done later in settings.
    public var isOptional: Bool { self > .folder }

    public var next: FirstRunStep? { Self.allCases.firstIndex(of: self).flatMap { Self.allCases.dropFirst($0 + 1).first } }
    public var previous: FirstRunStep? { Self.allCases.firstIndex(of: self).flatMap { $0 > 0 ? Self.allCases[$0 - 1] : nil } }

    /// A step past the folder writes into the folder, so it opens only once one is open.
    public func isReachable(folderOpen: Bool) -> Bool { self <= .folder || folderOpen }

    public static func < (a: Self, b: Self) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }
}

/// How the folder step starts: an empty folder that the term step fills, or a folder Folio has written before.
public enum FolderStart: String, CaseIterable, Sendable, Hashable {
    case fresh, existing
}

/// What a picked folder holds, read from its top two levels: enough to tell a GIST folder from anything else without
/// walking a whole iCloud tree on the first screen.
public enum FolderKind: Hashable, Sendable {
    case empty
    case gist(semesters: Int, courses: Int)
    case other

    public init(_ tree: FolderTree) {
        // Hidden files other than `.folio` are the system's (.DS_Store, Icon\r, a sync's markers), not the student's.
        let children = tree.children.filter { $0.name == StandardLayout.metadataFolder || !$0.name.hasPrefix(".") }
        guard !children.isEmpty else { self = .empty; return }
        let semesters = children.filter { !$0.isFile && SemesterFolder(name: $0.name) != nil }
        let marked = !semesters.isEmpty || children.contains {
            !$0.isFile && ($0.name == StandardLayout.metadataFolder || $0.name == StandardLayout.creditedFolder)
        }
        guard marked else { self = .other; return }
        let courses = semesters.flatMap(\.children).filter { !$0.isFile && StandardLayout.isCourseFolderName($0.name) }
        self = .gist(semesters: semesters.count, courses: courses.count)
    }

    /// The start this folder fits, so picking a GIST folder from "새로 시작" opens it rather than refusing it.
    public var start: FolderStart? {
        switch self {
        case .empty: .fresh
        case .gist: .existing
        case .other: nil
        }
    }

    /// Why the folder can't be used for `start`. A fresh start lays semester folders at the top, where a GIST folder
    /// holds nothing else, so it needs the folder empty.
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

/// Whether the remembered folder can be opened on this device. The files the app reads as it opens (transcript,
/// settings, catalog, every course.json) must be here: in an iCloud folder not yet downloaded they are placeholders,
/// and reading one would show an empty term over the real one.
public enum FolderAvailability: Hashable, Sendable {
    case ready
    case missing
    case downloading(done: Int, total: Int)

    /// `downloaded` holds one flag per file the app reads as it opens the folder.
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
