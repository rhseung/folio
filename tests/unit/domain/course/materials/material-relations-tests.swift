import Foundation
import Testing

@testable import FolioDomain

struct MaterialRelationsTests {
    let device = UUID()
    let now = Date(timeIntervalSince1970: 0)

    func course() -> CourseFile {
        var file = CourseFile(course: Course(device: device, at: now, title: "컴파일러"))
        file.materials = ["Lectures/03_Chapter.pdf", "Lectures/03-1_Handout.pdf", "Study/LR 정리.pdf", "Exams/Midterm/Guide.pdf"]
            .map { Material(device: device, at: now, path: $0, role: .lecture, status: .classified) }
        let chapter = Unit(device: device, at: now, title: "Syntax Analysis", order: 1)
        let section = Unit(device: device, at: now, title: "LR Parsing", order: 1, parentId: chapter.id)
        file.units = [chapter, section]
        file.sessions = [Session(device: device, at: now, week: 3, date: now)]
        file.exams = [Exam(device: device, at: now, title: "중간고사", folder: "Midterm")]
        file.toggle(session: file.sessions[0].id, unit: section.id)
        return file
    }

    var chapter: (CourseFile) -> UUID { { $0.units[0].id } }
    var section: (CourseFile) -> UUID { { $0.units[1].id } }

    @Test func aSessionGathersItsUnitsAndTheirParentsFiles() {
        var file = course()
        file.setMaterial(file.materials[0].id, unit: chapter(file), linked: true)
        file.linkMaterial(file.materials[1].id, session: file.sessions[0].id)
        let session = MaterialTarget.session(file.sessions[0].id)
        #expect(file.routes(of: file.materials[0], to: session) == [.unit(chapter(file))])
        #expect(file.routes(of: file.materials[1], to: session) == [.direct])
        #expect(file.routes(of: file.materials[2], to: session).isEmpty)
        #expect(file.materials(of: session).map(\.material.path) == ["Lectures/03_Chapter.pdf", "Lectures/03-1_Handout.pdf"])
    }

    @Test func aUnitGathersItsSessionsFilesButNotItsParentsFiles() {
        var file = course()
        file.setMaterial(file.materials[0].id, unit: chapter(file), linked: true)
        file.linkMaterial(file.materials[1].id, session: file.sessions[0].id)
        file.setMaterial(file.materials[1].id, unit: section(file), linked: true)
        file.setMaterial(file.materials[2].id, unit: section(file), linked: true)
        let unit = MaterialTarget.unit(section(file))
        #expect(file.routes(of: file.materials[0], to: unit).isEmpty)
        #expect(file.routes(of: file.materials[1], to: unit) == [.direct, .session(file.sessions[0].id)])
        #expect(file.routes(of: file.materials[2], to: unit) == [.direct])
    }

    @Test func aFilesUnitsSayWhichAreLinkedThroughASession() {
        var file = course()
        file.linkMaterial(file.materials[1].id, session: file.sessions[0].id)
        file.setMaterial(file.materials[1].id, unit: chapter(file), linked: true)
        let units = file.units(of: file.materials[1])
        #expect(units.map(\.unit.title) == ["Syntax Analysis", "LR Parsing"])
        #expect(units.map(\.routes) == [[.direct], [.session(file.sessions[0].id)]])
    }

    @Test func anExamGathersItsFolderAndItsLinks() {
        var file = course()
        let exam = file.exams[0].id
        file.setMaterial(file.materials[2].id, exam: exam, linked: true)
        #expect(file.routes(of: file.materials[3], to: .exam(exam)) == [.folder])
        #expect(file.routes(of: file.materials[2], to: .exam(exam)) == [.direct])
        #expect(file.materials(for: file.exams[0]).map(\.path) == ["Study/LR 정리.pdf", "Exams/Midterm/Guide.pdf"])
        file.materials[3].path = "Exams/Midterm 2/Guide.pdf"
        #expect(file.routes(of: file.materials[3], to: .exam(exam)).isEmpty)
    }

    @Test func aSplitLectureBelongsWithItsUnitsAndTheirSessions() {
        var file = course()
        let lecture = file.materials[0].id
        file.split(
            lecture,
            into: [
                LectureCut(unit: chapter(file), firstPage: 1, lastPage: 4),
                LectureCut(unit: section(file), firstPage: 5, lastPage: 12),
            ], device: device, now: now)
        #expect(file.materials[0].unitIds.isEmpty)
        #expect(file.routes(of: file.materials[0], to: .unit(section(file))) == [.pages])
        #expect(file.routes(of: file.materials[0], to: .unit(chapter(file))) == [.pages])
        #expect(file.routes(of: file.materials[0], to: .session(file.sessions[0].id)) == [.unit(section(file)), .unit(chapter(file))])
        #expect(file.units(of: file.materials[0]).map(\.routes) == [[.pages], [.pages]])

        file.setMaterial(lecture, unit: section(file), linked: true)
        #expect(file.routes(of: file.materials[0], to: .unit(section(file))) == [.direct, .pages])

        file.split(lecture, into: [], device: device, now: now)
        #expect(file.routes(of: file.materials[0], to: .unit(chapter(file))).isEmpty)
        #expect(file.routes(of: file.materials[0], to: .unit(section(file))) == [.direct])
        file.setMaterial(lecture, unit: section(file), linked: false)
        #expect(file.routes(of: file.materials[0], to: .session(file.sessions[0].id)).isEmpty)
    }

    @Test func aUnitDoesNotGatherTheFilesItsParentSplits() {
        var file = course()
        file.split(file.materials[0].id, into: [LectureCut(unit: chapter(file), firstPage: 1, lastPage: 4)], device: device, now: now)
        #expect(file.routes(of: file.materials[0], to: .unit(section(file))).isEmpty)
        #expect(file.routes(of: file.materials[0], to: .session(file.sessions[0].id)) == [.unit(chapter(file))])
    }

    @Test func aParentCycleEnds() {
        var file = course()
        file.units[0].parentId = file.units[1].id
        file.setMaterial(file.materials[0].id, unit: chapter(file), linked: true)
        #expect(file.routes(of: file.materials[0], to: .session(file.sessions[0].id)) == [.unit(chapter(file))])
    }
}
