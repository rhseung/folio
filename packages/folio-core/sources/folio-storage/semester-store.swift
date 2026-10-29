import FolioDomain
import Foundation

extension GISTStore {
    public func addSemester(_ semester: Semester) throws {
        // Only a missing file starts empty; one that fails to read must not be replaced by a single-semester file.
        var doc = FileManager.default.fileExists(atPath: transcriptURL.path) ? try loadTranscript() : StoredDocument(new: Transcript())
        guard !doc.model.semesters.contains(where: { $0.year == semester.year && $0.term == semester.term }) else {
            throw MoveJournal.Failure.targetExists(semester.folder?.name ?? "\(semester.year)")
        }
        doc.model.semesters.append(semester)
        if let folder = semester.folder {
            try FileManager.default.createDirectory(at: url.appending(path: folder.name), withIntermediateDirectories: true)
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
        guard let semesterFolder = semester.folder else { throw MoveJournal.Failure.targetExists(folderName) }
        let folder = url.appending(path: semesterFolder.name).appending(path: folderName)
        guard !FileManager.default.fileExists(atPath: folder.path) else {
            throw MoveJournal.Failure.targetExists("\(semesterFolder.name)/\(folderName)")
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
