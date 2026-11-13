import FolioActions
import FolioDomain
import FolioFixtures
import FolioStorage
import Foundation
import Testing

/// A removal settles every pointer at the removed item, so the save that follows has nothing new to refuse.
struct RemoveActionTests {
    static let course = UUID(uuidString: "C0000000-0000-4000-8000-000000000002")!
    let device = UUID()
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let gist: GISTStore

    init() throws {
        gist = GISTStore(url: try Fixture.standard.copyToTemp())
    }

    func run(_ action: some Action) throws {
        try action.run(ActionContext(gist: gist, device: device, now: now))
    }

    func file() throws -> CourseFile { try ActionContext(gist: gist, device: device).file(Self.course) }

    func edit(_ change: (inout CourseFile) -> Void) throws {
        let store = try ActionContext(gist: gist, device: device).store(Self.course)
        var doc = try store.load()
        change(&doc.model)
        try store.save(doc)
    }

    // Only a unit note keeps units of its own; any other kind would drop them on the way in.
    func note(_ path: String, units: [UUID] = [], exam: UUID? = nil) -> NoteEntry {
        NoteEntry(
            id: UUID(), device: device, at: now, path: path,
            meta: NoteMeta(kind: units.isEmpty ? .free : .unit, unitIds: units, examId: exam))
    }

    func problems(_ title: String, units: [UUID]) -> ProblemSet {
        ProblemSet(device: device, at: now, title: title, problems: [.init(number: "1", unitIds: units), .init(number: "2")])
    }

    /// Tracks the fixture's files and hangs one of them on a session, a problem set and an assignment.
    func linkedMaterial() throws -> UUID {
        try run(MaterialTrack(course: Self.course))
        let session = UUID()
        try run(SessionAdd(id: session, course: Self.course, date: now))
        let material = try #require(try file().materials.first { $0.path.hasSuffix("Seating.pdf") }).id
        try edit { f in
            f.linkMaterial(material, session: session, firstPage: 1, lastPage: 2)
            var set = problems("연습 1", units: [])
            set.materialId = material
            set.solutionMaterialId = material
            f.problemSets.append(set)
            var a = Assignment(device: device, at: now, title: "HW9")
            a.problemMaterialId = material
            a.submissionMaterialIds = [material]
            f.assignments.append(a)
        }
        return material
    }

    func expectNoPointer(at material: UUID) throws {
        let f = try file()
        #expect(!f.materials.contains { $0.id == material })
        #expect(f.sessions.allSatisfy { !$0.materials.contains { $0.materialId == material } })
        #expect(f.problemSets.allSatisfy { $0.materialId != material && $0.solutionMaterialId != material })
        #expect(f.assignments.allSatisfy { $0.problemMaterialId != material && !$0.submissionMaterialIds.contains(material) })
    }

    @Test func aUnitWithLinkedNotesMaterialsAndProblemsGoes() throws {
        let parent = Unit(device: device, at: now, title: "그래프", order: 90)
        let unit = Unit(device: device, at: now, title: "트리", order: 1, parentId: parent.id)
        let child = Unit(device: device, at: now, title: "스패닝 트리", order: 1, parentId: unit.id)
        let exam = Exam(device: device, at: now, title: "기말고사")
        try run(MaterialTrack(course: Self.course))
        try edit { f in
            f.units += [parent, unit, child]
            f.materials[0].unitIds.append(unit.id)
            f.notes.append(note("Notes/트리 대충.md", units: [unit.id]))
            f.problemSets.append(problems("트리 연습", units: [unit.id]))
            var a = Assignment(device: device, at: now, title: "HW8")
            a.unitIds = [unit.id]
            f.assignments.append(a)
            var e = exam
            e.plan = [
                ExamPlanItem(day: LocalDate(year: 2026, month: 12, day: 1)!, title: "트리 복습", target: .init(kind: .unit, id: unit.id)),
                ExamPlanItem(day: LocalDate(year: 2026, month: 12, day: 2)!, title: "트리 카드", target: .init(kind: .quiz, id: unit.id)),
            ]
            f.exams.append(e)
        }

        try run(UnitRemove(course: Self.course, unit: unit.id))

        let f = try file()
        #expect(!f.units.contains { $0.id == unit.id })
        #expect(f.units.first { $0.id == child.id }?.parentId == parent.id)
        #expect(f.materials.allSatisfy { !$0.unitIds.contains(unit.id) })
        #expect(f.notes.allSatisfy { !$0.unitIds.contains(unit.id) })
        #expect(f.problemSets.allSatisfy { $0.problems.allSatisfy { !$0.unitIds.contains(unit.id) } })
        #expect(f.problemSets.first { $0.title == "트리 연습" }?.problems.count == 2)
        #expect(f.assignments.allSatisfy { !$0.unitIds.contains(unit.id) })
        let plan = try #require(f.exams.first { $0.id == exam.id }?.plan)
        #expect(plan.map(\.title) == ["트리 복습", "트리 카드"])
        #expect(plan.allSatisfy { $0.target == nil })
    }

    /// A class note reads its units from its session, so it loses the unit when the session does.
    @Test func aSessionNoteKeepsItsUnitsUntilTheUnitGoes() throws {
        let session = UUID()
        let unit = Unit(device: device, at: now, title: "매칭", order: 90)
        try run(SessionAdd(id: session, course: Self.course, date: now))
        try edit { f in f.units.append(unit) }
        try edit { f in f.toggle(session: session, unit: unit.id) }
        let note = UUID()
        try run(SessionNote(id: note, course: Self.course, session: session, kind: .rough))
        func units() throws -> [UUID] {
            let f = try file()
            return f.meta(of: try #require(f.notes.first { $0.id == note })).unitIds
        }
        #expect(try units() == [unit.id])

        try run(UnitRemove(course: Self.course, unit: unit.id))

        #expect(try units().isEmpty)
    }

    @Test func anExamWithASummaryNoteAndLinkedMaterialsGoes() throws {
        let exam = Exam(device: device, at: now, title: "기말고사")
        try run(MaterialTrack(course: Self.course))
        try edit { f in
            f.exams.append(exam)
            f.materials[0].examIds.append(exam.id)
            f.notes.append(note("Notes/기말 요약.md", exam: exam.id))
        }

        try run(ExamRemove(course: Self.course, exam: exam.id))

        let f = try file()
        #expect(!f.exams.contains { $0.id == exam.id })
        #expect(f.materials.allSatisfy { !$0.examIds.contains(exam.id) })
        #expect(f.notes.allSatisfy { $0.examId != exam.id })
        #expect(f.notes.contains { $0.path == "Notes/기말 요약.md" })
    }

    @Test func untrackingAMaterialASessionUsesLetsGoOfIt() throws {
        let material = try linkedMaterial()
        try run(MaterialUntrack(course: Self.course, material: material))
        try expectNoPointer(at: material)
    }

    @Test func trashingAMaterialASessionUsesLetsGoOfIt() throws {
        let material = try linkedMaterial()
        try run(MaterialTrash(course: Self.course, material: material))
        try expectNoPointer(at: material)
    }

    @Test func removingAProblemSetClearsPlanItemsOnIt() throws {
        let set = problems("연습 2", units: [])
        var exam = Exam(device: device, at: now, title: "기말고사")
        exam.plan = [
            ExamPlanItem(day: LocalDate(year: 2026, month: 12, day: 1)!, title: "연습 2 풀기", target: .init(kind: .problemSet, id: set.id))
        ]
        try edit { f in
            f.problemSets.append(set)
            f.exams.append(exam)
        }

        try run(ProblemSetRemove(course: Self.course, set: set.id))

        let f = try file()
        #expect(!f.problemSets.contains { $0.id == set.id })
        #expect(f.exams.first { $0.id == exam.id }?.plan.first?.target == nil)
    }

    @Test func relinkingOntoADuplicateMovesProblemSetPointers() {
        let device = UUID(), now = Date(timeIntervalSince1970: 0)
        let original = Material(device: device, at: now, path: "Exercises/old.pdf", status: .classified)
        let dup = Material(device: device, at: now, path: "Exercises/new.pdf", status: .classified)
        var set = ProblemSet(device: device, at: now, title: "연습", problems: [.init(number: "1")])
        set.materialId = dup.id
        set.solutionMaterialId = dup.id
        var f = CourseFile(course: Course(device: device, at: now, title: "그래프 이론"))
        f.materials = [original, dup]
        f.problemSets = [set]

        f.relinkMaterial(original.id, to: dup.path, hash: nil, size: nil, bookmark: nil, device: device, now: now)

        #expect(f.problemSets[0].materialId == original.id)
        #expect(f.problemSets[0].solutionMaterialId == original.id)
        #expect(f.violations.isEmpty)
    }
}
