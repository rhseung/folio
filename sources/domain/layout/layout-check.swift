public enum LayoutCheck {
    public static func issues(in gist: FolderTree, extraAssignmentPrefixes: [String] = []) -> [LayoutIssue] {
        var issues: [LayoutIssue] = []
        func courses(in folder: FolderTree, at base: String, admin: Bool) {
            for child in folder.children {
                let path = "\(base)/\(child.name)"
                if child.isFile {
                    issues.append(.init(.fileInSemesterFolder, path))
                } else if admin && child.name == StandardLayout.adminFolder {
                    continue
                } else if !StandardLayout.isCourseFolderName(child.name) {
                    issues.append(.init(.invalidCourseFolderName, path))
                } else {
                    issues += courseIssues(child, at: path, extraAssignmentPrefixes: extraAssignmentPrefixes)
                }
            }
        }

        for item in gist.children {
            if item.name == StandardLayout.metadataFolder { continue }
            if item.name == StandardLayout.creditedFolder, !item.isFile {
                for source in item.children {
                    let path = "\(item.name)/\(source.name)"
                    if source.isFile {
                        issues.append(.init(.fileInSemesterFolder, path))
                    } else {
                        courses(in: source, at: path, admin: false)
                    }
                }
                continue
            }
            guard SemesterFolder(name: item.name) != nil, !item.isFile else {
                issues.append(.init(.unexpectedRootItem, item.name))
                continue
            }
            courses(in: item, at: item.name, admin: true)
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
                    guard !item.isFile else {
                        issues.append(.init(.invalidExamFolder, itemPath))
                        continue
                    }
                    if item.name == StandardLayout.legacyPastExamsFolder { issues.append(.init(.legacyFolder, itemPath)) }
                }
            case .notes:
                if entry[child: StandardLayout.legacyNoteExportsFolder]?.isFile == false {
                    issues.append(.init(.legacyFolder, "\(path)/\(StandardLayout.legacyNoteExportsFolder)"))
                }
            default:
                break
            }
        }
        return issues
    }
}
