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
