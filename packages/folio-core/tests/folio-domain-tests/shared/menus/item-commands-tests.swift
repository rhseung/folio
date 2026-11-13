import FolioDomain
import Foundation
import PropertyBased
import Testing

/// Every kind's menu (#403): rows by group, delete alone at the end, and only the rows the item's data allows.
struct ItemCommandsTests {
    let device = UUID()
    let now = Date(timeIntervalSince1970: 1_793_000_000)

    func course() -> CourseFile {
        var file = CourseFile(course: Course(device: device, at: now, title: "그래프 이론"))
        file.units = [Unit(device: device, at: now, title: "매칭", order: 0), Unit(device: device, at: now, title: "흐름", order: 1)]
        file.units.append(Unit(device: device, at: now, title: "최대 매칭", order: 0, parentId: file.units[0].id))
        file.exams = [Exam(device: device, at: now, title: "중간고사", folder: "중간고사"), Exam(device: device, at: now, title: "기말고사")]
        file.assignments = [Assignment(device: device, at: now, title: "HW 3")]
        file.materials = [
            Material(device: device, at: now, path: "Lectures/05_Matchings.pdf", role: .lecture, status: .classified),
            Material(device: device, at: now, path: "Assignments/HW03/code", isFolder: true, status: .classified),
            Material(device: device, at: now, path: "Lectures/gone.pdf", role: .lecture, status: .missing),
        ]
        return file
    }

    func ordered<C: ItemCommand>(_ menu: [C], removes: Bool = true) {
        #expect(menu.map(\.group) == menu.map(\.group).sorted())
        if removes { #expect(menu.last?.group == .remove) }
        #expect(menu.filter { $0.group == .remove }.count <= 1)
    }

    static let hosts: [MenuHost] = [.own, .elsewhere, .list, .unit(UUID()), .exam(UUID())]

    // MARK: Order on every kind

    @Test func everyKindIsInGroupOrderWithDeleteLast() async {
        let f = course()
        await propertyCheck(input: Gen.int(in: 0...4), Gen.bool, Gen.bool, Gen.bool) { host, a, b, c in
            let host = Self.hosts[host]
            ordered(f.commands(for: f.exams[a ? 0 : 1], host: host))
            ordered(f.commands(for: f.assignments[0], host: host, revealable: a))
            ordered(f.commands(for: f.units[a ? 0 : 2], host: host, dueToday: b))
            ordered(NoteMenuCommand.commands(host: host, builtPDF: a, builds: b, review: c ? .writing : nil, finder: a))
            ordered(f.commands(for: f.materials[a ? 0 : 1], host: host, pdf: b ? UUID() : nil, mac: c))
            ordered(CourseMenuCommand.commands(host: host, recordable: a, order: (b ? 0 : 1, 2), finder: c), removes: false)
            ordered(SemesterMenuCommand.commands(host: host, addsCourse: a, folded: b), removes: false)
            ordered(RecordingMenuCommand.commands(host: host, transcribes: a, hasTranscript: b))
            ordered(PersonMenuCommand.commands(host: host, hasMail: a))
        }
        ordered(ComponentMenuCommand.commands(addsScore: true, index: 1, count: 3))
        ordered(ScoreMenuCommand.commands(excused: false))
        ordered(CardMenuCommand.commands(solvesWrong: true))
        ordered(ProblemSetMenuCommand.commands(hasSheet: true, hasSolution: true))
        ordered(ProblemMenuCommand.commands(hasSheet: true, hasUnits: true), removes: false)
        ordered(RequirementMenuCommand.commands)
        ordered(CodeMenuCommand.commands)
        ordered(ExamPlanItem.commands(done: true))
    }

    /// The item's own screen leaves "열기" out; everywhere else the menu leads with it.
    @Test func openLeadsOffTheItemsOwnScreen() {
        let f = course()
        #expect(f.commands(for: f.exams[0], host: .elsewhere).first == .open)
        #expect(!f.commands(for: f.exams[0], host: .own).contains(.open))
        #expect(f.commands(for: f.assignments[0], host: .elsewhere, revealable: false).first == .open)
        #expect(!f.commands(for: f.units[0], host: .own, dueToday: false).contains(.open))
        #expect(NoteMenuCommand.commands(host: .elsewhere, builtPDF: false, builds: false, review: nil, finder: false).first == .open)
    }

    // MARK: Per kind

    @Test func anExamTakesFilesOnlyOnceItHasAFolder() {
        let f = course()
        #expect(f.commands(for: f.exams[0], host: .own) == [.summary, .addFiles, .edit, .share, .remove])
        #expect(f.commands(for: f.exams[1], host: .own) == [.summary, .edit, .share, .remove])
    }

    @Test func anAssignmentShowsItsStatusAndItsFolderOnlyWhereThereIsOne() {
        var f = course()
        f.assignments[0].status = .doing
        #expect(f.commands(for: f.assignments[0], host: .own, revealable: false) == [.addFiles, .status(.doing), .edit, .share, .remove])
        #expect(f.commands(for: f.assignments[0], host: .own, revealable: true).contains(.showInFinder))
    }

    /// Up and down only in the list that holds the units in order, and only the ways a unit can go among its siblings.
    @Test func aUnitMovesOnlyInTheListAndOnlyWhereItCan() {
        let f = course()
        let first = f.commands(for: f.units[0], host: .list, dueToday: false)
        #expect(first.contains(.moveDown) && !first.contains(.moveUp))
        let last = f.commands(for: f.units[1], host: .list, dueToday: false)
        #expect(last.contains(.moveUp) && !last.contains(.moveDown))

        // An only child has nowhere to go.
        let child = f.commands(for: f.units[2], host: .list, dueToday: false)
        #expect(!child.contains(.moveUp) && !child.contains(.moveDown))
        #expect(!f.commands(for: f.units[0], host: .elsewhere, dueToday: false).contains(.moveDown))
        #expect(f.commands(for: f.units[0], host: .elsewhere, dueToday: true).contains(.skipToday))
        #expect(!f.commands(for: f.units[0], host: .elsewhere, dueToday: false).contains(.skipToday))
    }

    /// Only a review note has the 작성 완료 row, and only once it is one.
    @Test func aNoteHasTheReviewRowOnlyWhenItReviewsAClass() {
        let plain = NoteMenuCommand.commands(host: .own, builtPDF: false, builds: false, review: nil, finder: false)
        #expect(plain == [.edit, .move, .share, .remove])
        let review = NoteMenuCommand.commands(host: .own, builtPDF: false, builds: false, review: .writing, finder: false)
        #expect(review.contains(.review(.writing)))
        // A class without a note yet: nothing for a note's menu to check.
        #expect(
            !NoteMenuCommand.commands(host: .own, builtPDF: false, builds: false, review: .needed, finder: false).contains {
                $0.group == .state
            })
        let tex = NoteMenuCommand.commands(host: .own, builtPDF: true, builds: true, review: nil, finder: true)
        #expect(tex == [.openPDF, .build, .edit, .move, .share, .showInFinder, .remove])
    }

    @Test func aMissingFileHasOnlyItsTwoWaysOut() {
        let f = course()
        #expect(f.commands(for: f.materials[2], host: .own, pdf: nil, mac: true) == [.relink, .untrack])
    }

    /// A folder opens only in Finder and has no link to share; the screen that links a file can let it go.
    @Test func aFileAndAFolderByPlatformAndHost() {
        var f = course()
        #expect(f.commands(for: f.materials[1], host: .elsewhere, pdf: nil, mac: false) == [.edit, .move, .remove])
        #expect(
            f.commands(for: f.materials[1], host: .elsewhere, pdf: nil, mac: true)
                == [.open, .openInEditor, .edit, .move, .showInFinder, .remove])
        let exam = f.exams[0].id
        #expect(!f.commands(for: f.materials[0], host: .exam(exam), pdf: nil, mac: false).contains(.unlink(.exam(exam))))
        f.materials[0].examIds = [exam]
        #expect(f.commands(for: f.materials[0], host: .exam(exam), pdf: nil, mac: false).contains(.unlink(.exam(exam))))
    }

    @Test func aCourseMovesOnlyInTheSidebarAndHasNoDelete() {
        #expect(
            CourseMenuCommand.commands(host: .list, recordable: false, order: (0, 3), finder: false) == [.open, .edit, .moveDown, .share])
        #expect(
            CourseMenuCommand.commands(host: .own, recordable: true, order: (1, 3), finder: true) == [
                .record, .edit, .share, .showInFinder,
            ])
    }

    @Test func aScoreCountsUnlessExcused() {
        #expect(ScoreMenuCommand.commands(excused: false).first == .counts(true))
        #expect(ScoreMenuCommand.commands(excused: true).first == .counts(false))
        #expect(ComponentMenuCommand.commands(addsScore: false, index: 0, count: 1) == [.edit, .remove])
    }
}
