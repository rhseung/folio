/// `path` is relative to the GIST root.
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
        case invalidPastExamFileName
    }

    public var kind: Kind
    public var path: String

    public init(_ kind: Kind, _ path: String) {
        self.kind = kind
        self.path = path
    }
}

public enum LayoutCheck {
    public static func issues(in gist: FolderTree, extraAssignmentPrefixes: [String] = []) -> [LayoutIssue] {
        var issues: [LayoutIssue] = []
        for item in gist.children {
            if item.name == StandardLayout.metadataFolder { continue }
            guard SemesterFolder(name: item.name) != nil, !item.isFile else {
                issues.append(.init(.unexpectedRootItem, item.name))
                continue
            }
            for child in item.children {
                let path = "\(item.name)/\(child.name)"
                if child.isFile {
                    issues.append(.init(.fileInSemesterFolder, path))
                } else if child.name == StandardLayout.adminFolder {
                    continue
                } else if !StandardLayout.isCourseFolderName(child.name) {
                    issues.append(.init(.invalidCourseFolderName, path))
                } else {
                    issues += courseIssues(child, at: path, extraAssignmentPrefixes: extraAssignmentPrefixes)
                }
            }
        }
        return issues
    }

    static func courseIssues(_ course: FolderTree, at base: String, extraAssignmentPrefixes: [String]) -> [LayoutIssue] {
        var issues: [LayoutIssue] = []
        for entry in course.children {
            let path = "\(base)/\(entry.name)"
            if entry.isFile {
                issues.append(.init(.fileInCourseFolder, path))
                continue
            }
            switch CourseFolder(rawValue: entry.name) {
            case nil:
                issues.append(.init(.unknownCourseSubfolder, path))
            case .lectures:
                for file in entry.children where !(file.isFile && StandardLayout.isLectureFileName(file.name)) {
                    issues.append(.init(.invalidLectureFileName, "\(path)/\(file.name)"))
                }
            case .assignments:
                for item in entry.children
                where item.isFile || StandardLayout.assignmentFolder(item.name, extraPrefixes: extraAssignmentPrefixes) == nil {
                    issues.append(.init(.invalidAssignmentFolder, "\(path)/\(item.name)"))
                }
            case .exams:
                for item in entry.children {
                    let itemPath = "\(path)/\(item.name)"
                    guard !item.isFile, StandardLayout.isExamFolderName(item.name) else {
                        issues.append(.init(.invalidExamFolder, itemPath))
                        continue
                    }
                    if item.name == StandardLayout.pastExamsFolder {
                        for file in item.children where !(file.isFile && StandardLayout.isPastExamFileName(file.name)) {
                            issues.append(.init(.invalidPastExamFileName, "\(itemPath)/\(file.name)"))
                        }
                    }
                }
            default:
                break
            }
        }
        return issues
    }
}
