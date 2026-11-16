public struct LayoutIssue: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case unexpectedRootItem
        case fileInSemesterFolder
        case invalidCourseFolderName
        case fileInCourseFolder
        case unknownCourseSubfolder
        case invalidAssignmentFolder
        case invalidExamFolder
        case invalidLectureFileName
        case legacyFolder
    }

    public var kind: Kind
    public var path: String

    public init(_ kind: Kind, _ path: String) {
        self.kind = kind
        self.path = path
    }
}
