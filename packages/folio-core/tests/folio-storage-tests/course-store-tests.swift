import FolioDomain
import FolioFixtures
import FolioStorage
import Foundation
import Testing

struct CourseStoreTests {
    let device = UUID()
    let now = Date(timeIntervalSince1970: 2_000_000)

    func graphTheory() throws -> CourseStore {
        let gist = GISTStore(url: try Fixture.standard.copyToTemp())
        return try #require(try gist.courseStores().first { $0.url.lastPathComponent == "EC4207 그래프 이론" })
    }

    func refreshed(_ store: CourseStore) throws -> StoredDocument<CourseFile> {
        var doc = try store.load()
        try store.refreshMaterials(in: &doc.model, device: device, now: now)
        try store.save(doc)
        return try store.load()
    }

    @Test func registersEveryFileOnce() throws {
        let store = try graphTheory()
        let materials = try refreshed(store).model.materials
        #expect(materials.count == 13)
        #expect(materials.allSatisfy { $0.status == .classified && $0.hash != nil })
        #expect(materials.contains { $0.path == "Exams/Past/2024 Midterm (소순범).pdf" && $0.role == .pastExam })
        #expect(!materials.contains { $0.path.hasPrefix("Notes/") })

        #expect(try refreshed(store).model.materials == materials)
    }

    @Test func followsMovedAndRenamedFiles() throws {
        let store = try graphTheory()
        let before = try refreshed(store).model.materials
        let fm = FileManager.default

        // Moved: the bookmark still resolves.
        let lecture = try #require(before.first { $0.path == "Lectures/05_Matchings.pdf" })
        try fm.moveItem(at: store.url.appending(path: lecture.path), to: store.url.appending(path: "Exercises/05_Matchings.pdf"))

        // Replaced by an identical copy under a new name: only the hash matches.
        let syllabus = try #require(before.first { $0.path == "Syllabus/Syllabus.pdf" })
        let syllabusURL = store.url.appending(path: syllabus.path)
        let copy = store.url.appending(path: "Syllabus/OT.pdf")
        try fm.copyItem(at: syllabusURL, to: copy)
        try fm.removeItem(at: syllabusURL)

        // Deleted.
        let seating = try #require(before.first { $0.path == "Exams/Midterm/Seating.pdf" })
        try fm.removeItem(at: store.url.appending(path: seating.path))

        let after = try refreshed(store).model.materials
        #expect(after.count == before.count)
        #expect(after.first { $0.id == lecture.id }.map { ($0.path, $0.role) }! == ("Exercises/05_Matchings.pdf", .exercise))
        #expect(after.first { $0.id == syllabus.id }?.path == "Syllabus/OT.pdf")
        #expect(after.first { $0.id == seating.id }?.status == .missing)
    }

    @Test func codeProjectIsOneFolderMaterial() throws {
        let gist = GISTStore(url: try Fixture.standard.copyToTemp())
        let store = try #require(try gist.courseStores().first { $0.url.lastPathComponent == "EC4321 로봇공학" })
        let materials = try refreshed(store).model.materials
        let project = try #require(materials.first { $0.isFolder })
        #expect(project.path == "Assignments/Project01/robot")
        #expect(!materials.contains { $0.path.contains("main.py") })
    }

    @Test func transcriptLoads() throws {
        let gist = GISTStore(url: try Fixture.standard.copyToTemp())
        let semesters = try gist.loadTranscript().model.semesters
        #expect(semesters.compactMap(\.folder?.name) == ["2026-1", "2026-3"])
    }
}

struct SemesterStoreTests {
    @Test func addSemesterThenCourse() throws {
        let gist = GISTStore(url: try Fixture.standard.copyToTemp())
        let device = UUID()
        let semester = Semester(device: device, at: .now, year: 2027, term: .spring, start: LocalDate("2027-03-02"), end: LocalDate("2027-06-18"))
        try gist.addSemester(semester)
        #expect(FileManager.default.fileExists(atPath: gist.url.appending(path: "2027-1").path))
        #expect(throws: (any Error).self) { try gist.addSemester(Semester(device: device, at: .now, year: 2027, term: .spring)) }

        let course = Course(device: device, at: .now, semesterId: semester.id, title: "확률과 통계")
        try gist.createCourse(course, folderName: "MM3001 확률과 통계", in: semester)
        #expect(try gist.courseStores().contains { $0.url.lastPathComponent == "MM3001 확률과 통계" })
        #expect(throws: (any Error).self) { try gist.createCourse(course, folderName: "MM3001 확률과 통계", in: semester) }

        var changed = semester
        changed.end = LocalDate("2027-06-25")
        try gist.updateSemester(changed)
        #expect(try gist.loadTranscript().model.semesters.first { $0.id == semester.id }?.end == LocalDate("2027-06-25"))
    }
}
