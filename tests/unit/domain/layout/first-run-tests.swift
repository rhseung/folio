import FolioDomain
import PropertyBased
import Testing

struct FirstRunTests {
    func folder(_ name: String, _ children: [FolderTree] = []) -> FolderTree { FolderTree(name: name, content: .folder(children)) }
    func file(_ name: String) -> FolderTree { FolderTree(name: name, content: .file(size: 1)) }

    @Test func stepsRunInOrderAndOnlyTheFolderIsRequiredPastTheWelcome() {
        #expect(FirstRunStep.allCases == [.welcome, .folder, .term, .profile, .permissions, .claude])
        #expect(FirstRunStep.welcome.previous == nil)
        #expect(FirstRunStep.claude.next == nil)
        #expect(FirstRunStep.folder.next == .term)
        #expect(FirstRunStep.term.previous == .folder)
        #expect(FirstRunStep.allCases.filter(\.isOptional) == [.term, .profile, .permissions, .claude])
    }

    @Test func stepsPastTheFolderWaitForOne() {
        #expect(FirstRunStep.allCases.filter { $0.isReachable(folderOpen: false) } == [.welcome, .folder])
        #expect(FirstRunStep.allCases.allSatisfy { $0.isReachable(folderOpen: true) })
    }

    @Test func aFolderWithOnlySystemFilesIsEmpty() {
        #expect(FolderKind(folder("GIST")) == .empty)
        #expect(FolderKind(folder("GIST", [file(".DS_Store"), file(".Icon\r")])) == .empty)
    }

    @Test func semesterFoldersAndTheirCoursesAreCounted() {
        let tree = folder(
            "GIST",
            [
                folder(".folio", [file("transcript.json")]),
                folder("2026-1", [folder("MA2001 선형대수학"), folder("_Admin"), file("수강신청.pdf")]),
                folder("2026-3", [folder("EC4207 그래프 이론"), folder("CS3104 컴퓨터 네트워크")]),
                folder("_Credited", [folder("영재고 AP")]),
            ])
        #expect(FolderKind(tree) == .gist(semesters: 2, courses: 3))
    }

    @Test func creditedCoursesUnderTheirSourceAreCounted() {
        let tree = folder(
            "GIST",
            [
                folder(".folio"),
                folder("_Credited", [folder("영재고 AP", [folder("GS1101 일반물리학 및 연습 I"), file("성적표.pdf")])]),
            ])
        #expect(FolderKind(tree) == .gist(semesters: 0, courses: 1))
    }

    @Test func onlyTheMetadataFolderStillMarksAFolioFolder() {
        #expect(FolderKind(folder("GIST", [folder(".folio")])) == .gist(semesters: 0, courses: 0))
        #expect(FolderKind(folder("GIST", [folder("_Credited")])) == .gist(semesters: 0, courses: 0))
    }

    @Test func anyOtherFolderIsNotOne() {
        #expect(FolderKind(folder("Documents", [folder("사진"), file("이력서.pdf")])) == .other)
        // A file named like a semester isn't one.
        #expect(FolderKind(folder("Documents", [file("2026-1")])) == .other)
    }

    @Test func eachStartTakesTheFolderItFits() {
        let gist = FolderKind.gist(semesters: 1, courses: 2)
        #expect(FolderKind.empty.problem(for: .fresh) == nil)
        #expect(gist.problem(for: .existing) == nil)
        #expect(gist.problem(for: .fresh) == .alreadyFolio)
        #expect(FolderKind.other.problem(for: .fresh) == .notEmpty)
        #expect(FolderKind.empty.problem(for: .existing) == .empty)
        #expect(FolderKind.other.problem(for: .existing) == .notFolio)
        #expect(FolderKind.empty.start == .fresh)
        #expect(gist.start == .existing)
        #expect(FolderKind.other.start == nil)
    }

    @Test func aFolderIsReadyWhenEveryLaunchFileIsHere() {
        #expect(FolderAvailability(exists: false, downloaded: [true]) == .missing)
        #expect(FolderAvailability(exists: true, downloaded: []) == .ready)
        #expect(FolderAvailability(exists: true, downloaded: [true, true]) == .ready)
        #expect(FolderAvailability(exists: true, downloaded: [true, false, false, true]) == .downloading(done: 2, total: 4))
        #expect(FolderAvailability.downloading(done: 1, total: 4).fraction == 0.25)
    }

    // MARK: Properties

    static let pool = [".DS_Store", ".hidden", "2026-1", "2025-3", "_Admin", "_Credited", ".folio", "사진", "EC4207 그래프 이론"]
    static let names = Gen.int(in: 0...(pool.count - 1)).map { pool[$0] }
    static let tops = zip(names, Gen.bool).array(of: 0...6)

    func tree(_ rows: [(String, Bool)]) -> FolderTree {
        folder("GIST", rows.map { name, isFolder in isFolder ? folder(name, [folder("EC4207 그래프 이론")]) : file(name) })
    }

    @Test func theStartAFolderFitsNeverRefusesIt() async {
        await propertyCheck(input: Self.tops) { rows in
            let kind = FolderKind(tree(rows))
            if let start = kind.start { #expect(kind.problem(for: start) == nil) }
            #expect(FolderStart.allCases.contains { kind.problem(for: $0) == nil } == (kind.start != nil))
        }
    }

    @Test func hiddenSystemFilesNeverChangeWhatAFolderIs() async {
        await propertyCheck(input: Self.tops) { rows in
            #expect(FolderKind(tree(rows + [(".DS_Store", false), (".Trash", true)])) == FolderKind(tree(rows)))
        }
    }

    @Test func availabilityCountsWhatIsHere() async {
        await propertyCheck(input: Gen.bool.array(of: 0...12)) { flags in
            let availability = FolderAvailability(exists: true, downloaded: flags)
            #expect((availability == .ready) == flags.allSatisfy { $0 })
            #expect((0...1).contains(availability.fraction))
        }
    }
}
