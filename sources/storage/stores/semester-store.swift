import FolioDomain
import Foundation

extension GISTStore {
    public func addSemester(_ semester: Semester) throws {
        // 파일이 없을 때만 비어 시작한다. 읽지 못한 파일을 학기 하나짜리 파일로 바꾸면 안 된다.
        var doc = FileManager.default.fileExists(atPath: transcriptURL.path) ? try loadTranscript() : StoredDocument(new: Transcript())
        guard !doc.model.semesters.contains(where: { $0.year == semester.year && $0.term == semester.term }) else {
            throw MoveJournal.Failure.targetExists(semester.folder?.name ?? "\(semester.year)")
        }
        doc.model.semesters.append(semester)
        if let folder = semester.coursesFolder {
            try FileManager.default.createDirectory(at: url.appending(path: folder), withIntermediateDirectories: true)
        }
        try save(doc)
    }

    public func updateSemester(_ semester: Semester) throws {
        var doc = try loadTranscript()
        guard let i = doc.model.semesters.firstIndex(where: { $0.id == semester.id }) else { return }
        doc.model.semesters[i] = semester
        try save(doc)
    }

    @discardableResult
    public func createCourse(_ course: Course, folderName: String, in semester: Semester) throws -> CourseStore {
        guard let parent = semester.coursesFolder else { throw MoveJournal.Failure.targetExists(folderName) }
        let folder = url.appending(path: parent).appending(path: folderName)
        guard !FileManager.default.fileExists(atPath: folder.path) else {
            throw MoveJournal.Failure.targetExists("\(parent)/\(folderName)")
        }
        let store = CourseStore(url: folder)
        try store.save(StoredDocument(new: CourseFile(course: course)))
        return store
    }
}

extension GISTStore {
    public func adminFiles(of semester: Semester) -> [URL] {
        guard let folder = semester.folder else { return [] }
        let admin = url.appending(path: folder.name).appending(path: StandardLayout.adminFolder)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: admin.path)) ?? []
        return names.filter { !$0.hasPrefix(".") }.sorted().map { admin.appending(path: $0) }
    }
}
