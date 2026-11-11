import FolioDomain
import Foundation
import PropertyBased
import Testing

private let lecture = AppLink(.material, UUID(), anchor: .page(12))
private let note = AppLink(.note, UUID())
private let quiz = AppLink.course(UUID(), page: .quiz)
private let other = AppLink(.note, UUID())

private func approx(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

struct PaneLayoutTests {
    // Three panes at 360pt beside 40pt strips with 8pt gaps: three open need 1096, two 776, one 456.
    static func fit(_ l: PaneLayout, _ room: Double) -> PaneLayout.Fit { l.fit(room: room, minWidth: 360, strip: 40, gap: 8) }

    static func three() -> PaneLayout {
        var l = PaneLayout(links: [lecture, note, quiz], limit: 3)!
        // Pressed in this order, so the lecture is the oldest press and the note the focus.
        l.press(0)
        l.press(2)
        l.press(1)
        return l
    }

    @Test func everyPaneOpensWhenTheyFit() {
        let f = Self.fit(Self.three(), 1216)
        #expect(f.folded.isEmpty)
        // Even shares of 1216 - 16.
        #expect(f.widths.allSatisfy { approx($0, 400) })
    }

    @Test func theOldestPressFoldsFirstAndTheFocusNever() {
        var l = Self.three()
        #expect(Self.fit(l, 956).folded == [0])
        #expect(Self.fit(l, 956).widths[0] == 40)
        #expect(Self.fit(l, 500).folded == [0, 2])
        // Far too narrow: the focused pane still stays open, with what there is.
        let tiny = Self.fit(l, 200)
        #expect(tiny.folded == [0, 2])
        #expect(approx(tiny.widths[1], 200 - 80 - 16))
        // Pressing the lecture's strip opens it and folds the quiz, now the oldest press.
        l.press(0)
        #expect(Self.fit(l, 956).folded == [2])
        #expect(l.focus == 0)
    }

    @Test func theOpenCountHangsOnTheWidthAlone() {
        // What a window resizing between two counts needs to know: 1096 holds three, 1095 two, 455 one.
        #expect(PaneLayout.openCount(3, room: 1096, minWidth: 360, strip: 40, gap: 8) == 3)
        #expect(PaneLayout.openCount(3, room: 1095, minWidth: 360, strip: 40, gap: 8) == 2)
        #expect(PaneLayout.openCount(3, room: 455, minWidth: 360, strip: 40, gap: 8) == 1)
        #expect(PaneLayout.openCount(1, room: 10, minWidth: 360, strip: 40, gap: 8) == 1)
        // The same folds as `fit`, with the widths for them.
        let l = Self.three()
        #expect(l.folded(open: 2) == Self.fit(l, 956).folded)
        #expect(l.widths(room: 956, folded: [0], minWidth: 360, strip: 40, gap: 8) == Self.fit(l, 956).widths)
    }

    @Test func aPaneFollowsItsOwnHistory() {
        var l = Self.three()
        l.show(.write, in: 2)
        // The quiz pane, not the focused note, goes on; its note mode stays only for the same target.
        l.open(AppLink.course(UUID(), page: .quiz), in: 2)
        #expect(l.links[1] == note && l.focus == 1)
        #expect(l.panes[2].noteMode == nil)
        l.show(.read, in: 0)
        l.open(AppLink(lecture.kind, lecture.id!, anchor: .page(3)), in: 0)
        #expect(l.panes[0].noteMode == .read)
    }

    @Test func aNarrowShareIsHeldAtTheMinimum() {
        let l = PaneLayout(links: [lecture, note, quiz], shares: [8, 1, 1], limit: 3)!
        let f = Self.fit(l, 1216)
        #expect(f.folded.isEmpty)
        #expect(f.widths[1] == 360 && f.widths[2] == 360)
        #expect(approx(f.widths[0], 1200 - 720))
    }

    @Test func besideSplitsTheFocusedPaneUntilTheLimit() {
        var l = PaneLayout(lecture)
        l.openBeside(note, limit: 2)
        #expect(l.links == [lecture, note] && l.focus == 1)
        #expect(l.shares == [0.5, 0.5])
        // At the limit the other pane shows it, and keeps its width.
        l.openBeside(quiz, limit: 2)
        #expect(l.links == [quiz, note] && l.focus == 0)
        // A pane already showing the target takes it, at the new page.
        l.openBeside(note.with(.heading("Hall")), limit: 2)
        #expect(l.links == [quiz, note.with(.heading("Hall"))] && l.focus == 1)
    }

    @Test func atTheLimitThePaneUnusedLongestShowsIt() {
        var l = Self.three()
        l.openBeside(other, limit: 3)
        #expect(l.links == [other, note, quiz] && l.focus == 0)
    }

    @Test func closingGivesTheWidthToTheNeighbor() {
        var l = PaneLayout(links: [lecture, note, quiz], shares: [2, 1, 1], limit: 3)!
        l.press(2)
        l.press(1)
        let middle = l.close(1)
        #expect(middle)
        #expect(l.links == [lecture, quiz] && approx(l.shares[0], 0.75) && l.focus == 1)
        let first = l.close(0)
        #expect(first)
        #expect(l.links == [quiz] && l.shares == [1])
        let last = l.close(0)
        #expect(!last)
    }

    @Test func swapsAndResizes() {
        var l = PaneLayout(links: [lecture, note], shares: [3, 1], limit: 2)!
        l.swap(0, 1)
        #expect(l.links == [note, lecture] && l.shares == [0.25, 0.75] && l.focus == 1)
        l.resize(divider: 0, to: 0.5)
        #expect(l.shares == [0.5, 0.5])
        l.resize(divider: 0, to: 0)
        #expect(approx(l.shares[0], PaneLayout.minShare))
        l.resize(divider: 1, to: 0.5)
        #expect(approx(l.shares[0], PaneLayout.minShare))
    }

    @Test func aDoubleClickEvensEveryPane() {
        var l = Self.three()
        l.resize(divider: 0, to: 0.2)
        l.resize(divider: 1, to: 0.9)
        l.even()
        #expect(l.shares.allSatisfy { approx($0, 1.0 / 3) })
        // Only the widths: the focus and which pane folds first stay.
        #expect(l.focus == 1 && l.links == [lecture, note, quiz])
        #expect(Self.fit(l, 776).folded == [0])
        var two = PaneLayout(links: [lecture, note], shares: [0.9, 0.1], limit: 2)!
        two.even()
        #expect(two.shares == [0.5, 0.5])
        var one = PaneLayout(lecture)
        one.even()
        #expect(one.shares == [1])
    }

    @Test func aPaneFoldedByHandStaysFoldedUntilPressed() {
        var l = Self.three()
        // The focused note folds by hand: the focus goes to the quiz, pressed before it.
        l.collapse(1)
        #expect(l.collapsed == [1] && l.focus == 2)
        // However wide the window: the rest open, the note a strip, the others sharing what it leaves.
        let wide = Self.fit(l, 2000)
        #expect(wide.folded == [1] && wide.widths[1] == 40)
        #expect(approx(wide.widths[0], wide.widths[2]))
        // Narrower, the room folds the oldest press as well; never the focus.
        #expect(Self.fit(l, 500).folded == [0, 1])
        // The last open pane can't fold.
        l.collapse(0)
        #expect(!l.canCollapse(2))
        l.collapse(2)
        #expect(l.collapsed == [0, 1] && l.focus == 2)
        // Pressing its strip opens it.
        l.press(1)
        #expect(l.collapsed == [0] && l.focus == 1)
        #expect(Self.fit(l, 2000).folded == [0])
    }

    @Test func closingTheLastOpenPaneOpensTheFocus() {
        var l = Self.three()
        l.collapse(0)
        l.collapse(2)
        let closed = l.close(1)
        #expect(closed)
        // The quiz was pressed more recently than the lecture: it takes the focus and opens.
        #expect(l.links == [lecture, quiz] && l.focus == 1 && l.collapsed == [0])
    }

    @Test func aFoldByHandRoundTripsThroughJSON() throws {
        var l = Self.three()
        l.collapse(0)
        let data = try JSONEncoder().encode(l)
        let back = try JSONDecoder().decode(PaneLayout.self, from: data)
        #expect(back.collapsed == [0] && back == l)
        let json = #"{"panes":[{"link":"\#(lecture.string)","share":1,"pressed":0},{"link":"\#(note.string)","share":1,"pressed":1,"collapsed":true}],"focus":1}"#
        let old = try JSONDecoder().decode(PaneLayout.self, from: Data(json.utf8))
        // A focus folded by hand, which the app never writes, moves to the pane left open.
        #expect(old.focus == 0 && old.collapsed == [1])
    }

    @Test func aPaneKeepsItsNoteModeUntilItShowsAnotherNote() {
        var l = PaneLayout(note)
        l.show(.read, in: 0)
        l.open(note.with(.heading("Hall")))
        #expect(l.focused.noteMode == .read)
        l.open(other)
        #expect(l.focused.noteMode == nil)
    }

    @Test func aSmallerLimitKeepsTheRecentPanes() {
        let l = Self.three().limited(to: 2)
        #expect(l.links == [note, quiz] && l.focus == 0)
        #expect(approx(l.shares.reduce(0, +), 1))
    }

    @Test func keepingSomePanesKeepsTheirFocusAndShares() throws {
        var l = Self.three()
        l.press(2)
        let kept = try #require(l.keeping { $0 != 0 })
        #expect(kept.links == [note, quiz] && kept.focus == 1)
        #expect(approx(kept.shares.reduce(0, +), 1))
        // The focused pane left out: the focus goes to the pane pressed most recently of those kept.
        let without = try #require(l.keeping { $0 != 2 })
        #expect(without.links == [lecture, note] && without.links[without.focus] == note)
        #expect(l.keeping { _ in false } == nil)
    }

    @Test func aLayoutIsTheClassWhoseNotesItShows() throws {
        let device = UUID(), now = Date(timeIntervalSince1970: 0)
        var a = Session(device: device, at: now, week: 1, date: now)
        a.roughNoteId = note.id
        var b = Session(device: device, at: now, week: 2, date: now)
        b.reviewNoteId = other.id
        let recording = Recording(device: device, at: now, sessionId: a.id, file: "Recordings/x.m4a")
        let file = CourseFile(course: Course(device: device, at: now, title: "그래프 이론"), sessions: [a, b], recordings: [recording])

        #expect(file.session(holding: note) == a.id && file.session(holding: other) == b.id)
        #expect(file.session(holding: AppLink(.recording, recording.id)) == a.id)
        // The class's own link opens the list of classes, which is no class's layout.
        #expect(file.session(holding: AppLink(.session, a.id)) == nil && file.session(holding: lecture) == nil)

        let lectureAndNote = try #require(PaneLayout(links: [lecture, note, quiz], limit: 3))
        #expect(lectureAndNote.session(in: [file]) == a.id)
        let twoClasses = try #require(PaneLayout(links: [note, other], limit: 3))
        #expect(twoClasses.session(in: [file]) == nil)
        let noClass = try #require(PaneLayout(links: [lecture, quiz], limit: 3))
        #expect(noClass.session(in: [file]) == nil)
        #expect(PaneLayout(AppLink(.recording, recording.id)).session(in: [file]) == a.id)
    }

    @Test func anotherTabJoinsAtAnEdgeWithItsFocus() {
        // A tab of one joining a tab of one halves the row; the other tab's focus comes along and takes the focus.
        var l = PaneLayout(lecture)
        let joined = l.merge(PaneLayout(note), at: 1, limit: 3)
        #expect(joined)
        #expect(l.links == [lecture, note] && l.focus == 1)
        #expect(l.shares.allSatisfy { approx($0, 0.5) })

        // A tab of two at the leading edge: two thirds of the row, split as it had it, its own focus kept.
        var two = PaneLayout(links: [quiz, other], shares: [0.75, 0.25], limit: 2)!
        two.press(1)
        var one = PaneLayout(lecture)
        let joinedTwo = one.merge(two, at: 0, limit: 3)
        #expect(joinedTwo)
        #expect(one.links == [quiz, other, lecture] && one.focus == 1)
        #expect(approx(one.shares[0], 0.5) && approx(one.shares[1], 1.0 / 6) && approx(one.shares[2], 1.0 / 3))
        // The joined panes count as pressed after the ones here, so the lecture folds first.
        #expect(one.folded(open: 2) == [2])
    }

    @Test func aTabThatDoesNotFitStaysWhereItIs() {
        var l = Self.three()
        let before = l
        #expect(!l.canMerge(PaneLayout(other), limit: 3))
        let joined = l.merge(PaneLayout(other), at: 1, limit: 3)
        #expect(!joined)
        #expect(l == before)
    }

    @Test func aPaneFoldedByHandInTheOtherTabStaysFolded() {
        var two = PaneLayout(links: [quiz, other], limit: 2)!
        two.collapse(1)
        var l = PaneLayout(lecture)
        l.merge(two, at: 1, limit: 3)
        #expect(l.collapsed == [2] && l.focus == 1)
    }

    @Test func roundTripsThroughJSON() throws {
        var l = Self.three()
        l.resize(divider: 0, to: 0.3)
        let data = try JSONEncoder().encode(l)
        let back = try JSONDecoder().decode(PaneLayout.self, from: data)
        #expect(back.links == l.links && back.focus == l.focus)
        #expect(zip(back.shares, l.shares).allSatisfy { approx($0, $1) })
        #expect(Self.fit(back, 956) == Self.fit(l, 956))
        #expect(String(data: data, encoding: .utf8)!.contains("folio:"))
        let broken = Data(#"{"panes":[{"link":"https://x","share":1,"pressed":0}],"focus":0}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(PaneLayout.self, from: broken) }
    }
}

struct PanePresetTests {
    static let course = UUID()

    static func session(material: UUID? = UUID(), page: Int? = 4, rough: UUID? = UUID(), review: UUID? = nil) -> Session {
        var s = Session(device: UUID(), at: Date(timeIntervalSince1970: 0), week: 10, date: Date(timeIntervalSince1970: 0))
        if let material { s.materials = [SessionMaterial(materialId: material, firstPage: page)] }
        s.roughNoteId = rough
        s.reviewNoteId = review
        return s
    }

    @Test func inClassIsTheLectureAndTheClassNote() throws {
        let s = Self.session()
        let l = try #require(PanePreset.inClass.layout(session: s, course: Self.course, limit: 3))
        #expect(l.links == [AppLink(.material, s.materials[0].materialId, anchor: .page(4)), AppLink(.note, s.roughNoteId!)])
        #expect(l.shares == [0.55, 0.45] && l.focus == 1)
    }

    @Test func rolesWithNothingAreLeftOut() throws {
        let s = Self.session()
        let l = try #require(PanePreset.review.layout(session: s, course: Self.course, limit: 3))
        #expect(l.links == [AppLink(.material, s.materials[0].materialId, anchor: .page(4)), AppLink(.note, s.roughNoteId!)])
        #expect(approx(l.shares[0], 0.4 / 0.7) && l.focus == 0)
        #expect(PanePreset.review.layout(session: Self.session(material: nil, rough: nil), course: Self.course, limit: 3) == nil)
    }

    // "복습" is written from the lecture and the class's note (2026-11-11 사용자); with two panes, the note in
    // between gives way and the review note, where the writing goes, stays.
    @Test func reviewIsTheLectureTheClassNoteAndTheReviewNote() throws {
        let s = Self.session(review: UUID())
        let lecture = AppLink(.material, s.materials[0].materialId, anchor: .page(4))
        let mac = try #require(PanePreset.review.layout(session: s, course: Self.course, limit: 3))
        #expect(mac.links == [lecture, AppLink(.note, s.roughNoteId!), AppLink(.note, s.reviewNoteId!)])
        #expect(approx(mac.shares[0], 0.4) && approx(mac.shares[1], 0.3) && approx(mac.shares[2], 0.3) && mac.focus == 2)
        let pad = try #require(PanePreset.review.layout(session: s, course: Self.course, limit: 2))
        #expect(pad.links == [lecture, AppLink(.note, s.reviewNoteId!)] && pad.focus == 1)
    }

    @Test func aLayoutGoesByItsPresetWhateverPageItIsAt() throws {
        let s = Self.session()
        var l = try #require(PanePreset.inClass.layout(session: s, course: Self.course, limit: 3))
        l.press(0)
        l.open(AppLink(.material, s.materials[0].materialId, anchor: .page(20)))
        l.resize(divider: 0, to: 0.7)
        #expect(PanePreset.matching(l, session: s, course: Self.course, limit: 3) == .inClass)
        l.openBeside(other, limit: 3)
        #expect(PanePreset.matching(l, session: s, course: Self.course, limit: 3) == nil)
    }

    @Test func classStartFillsInClassWithItsLecturesAndNote() throws {
        let lectures = [AppLink(.material, UUID(), anchor: .page(13)), AppLink(.material, UUID()), AppLink(.material, UUID())]
        let l = try #require(PanePreset.inClass.layout([.lecture: Array(lectures.prefix(2)), .classNote: [note]], focus: .classNote, limit: 3))
        #expect(l.links == [lectures[0], lectures[1], note] && l.focus == 2)
        #expect(approx(l.shares[0], 0.275) && approx(l.shares[1], 0.275) && approx(l.shares[2], 0.45))
        // Short of room, a lecture gives way before the note does.
        let pad = try #require(PanePreset.inClass.layout([.lecture: lectures, .classNote: [note]], focus: .classNote, limit: 2))
        #expect(pad.links == [lectures[0], note] && pad.shares == [0.55, 0.45] && pad.focus == 1)
        // Without the note, the lectures alone, focused on the first.
        let alone = try #require(PanePreset.inClass.layout([.lecture: [lectures[0]], .classNote: []], focus: .classNote, limit: 3))
        #expect(alone.links == [lectures[0]] && alone.shares == [1] && alone.focus == 0)
        #expect(PanePreset.inClass.layout([:], limit: 3) == nil)
    }

    @Test func builtInIDsAreUnique() {
        #expect(Set(PanePreset.builtIn.map(\.id)).count == PanePreset.builtIn.count)
        #expect(PanePreset.builtIn.allSatisfy { $0.slots.count == $0.shares.count && $0.name == nil && $0.isBuiltIn })
    }

    // "지금 배치 저장…" (2026-11-11 사용자): the class's own pages are kept as roles, anything else at its address.
    @Test func savingKeepsTheClassesPagesAsRolesAndTheRestAsAddresses() throws {
        let s = Self.session(review: UUID())
        let textbook = AppLink(.material, UUID(), anchor: .page(30))
        let at = try #require(PaneLayout(links: [AppLink(.note, s.reviewNoteId!), AppLink(.material, s.materials[0].materialId, anchor: .page(9)), textbook],
                                         shares: [2, 1, 1], limit: 3))
        let saved = PanePreset.saving(at, name: "정리", session: s, course: Self.course)
        #expect(saved.slots == [.role(.reviewNote), .role(.lecture), .link(textbook)])
        #expect(saved.name == "정리" && !saved.isBuiltIn && saved.needsClass && approx(saved.shares[0], 0.5))
        // Chosen in another class's tab, it takes that class's note and lecture, and the textbook as it was.
        let next = Self.session(page: nil, review: UUID())
        let filled = try #require(saved.layout(session: next, course: Self.course, limit: 3))
        #expect(filled.links == [AppLink(.note, next.reviewNoteId!), AppLink(.material, next.materials[0].materialId), textbook])
        #expect(saved.matches(filled, session: next, course: Self.course, limit: 3))
        // Off where there is no class to fill it from.
        #expect(saved.layout(session: nil, course: nil, limit: 3) == nil)
    }

    @Test func aLayoutOfAddressesAloneNeedsNoClass() throws {
        let grades = AppLink.place(.grades)
        let at = try #require(PaneLayout(links: [grades, other], limit: 3))
        let saved = PanePreset.saving(at, name: "성적과 메모", session: nil, course: nil)
        #expect(saved.slots == [.link(grades), .link(other)] && !saved.needsClass)
        #expect(saved.layout(session: nil, course: nil, limit: 3)?.links == [grades, other])
        #expect(PanePreset.matching(at, among: PanePreset.builtIn + [saved], in: nil, limit: 3) == saved)
    }

    @Test func aRoleInTwoSlotsTakesALinkEach() throws {
        let preset = PanePreset(name: "렉처 둘", slots: [.role(.lecture), .role(.classNote), .role(.lecture)], shares: [0.4, 0.2, 0.4])
        let lectures = [AppLink(.material, UUID()), AppLink(.material, UUID()), AppLink(.material, UUID())]
        let l = try #require(preset.layout([.lecture: lectures, .classNote: [note]], limit: 3))
        #expect(l.links == [lectures[0], note, lectures[1]])
        let spread = try #require(preset.layout([.lecture: lectures], limit: 3))
        #expect(spread.links == [lectures[0], lectures[1], lectures[2]])
    }

    @Test func aSavedLayoutRoundTripsThroughSettings() throws {
        let saved = PanePreset(name: "수업 + 성적", slots: [.role(.classNote), .link(.place(.grades))], shares: [0.7, 0.3])
        var settings = Settings(panePresets: [saved])
        settings.classStart.preset = saved.id
        let back = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
        #expect(back.panePresets == [saved] && back.classStartPreset == saved)
        #expect(back.presets.map(\.id) == PanePreset.builtIn.map(\.id) + [saved.id])
        // A deleted layout, or none chosen, starts a class in "수업 중".
        settings.panePresets = []
        #expect(settings.classStartPreset == .inClass && Settings().classStartPreset == .inClass)
        #expect(try JSONDecoder().decode(Settings.self, from: Data("{}".utf8)).panePresets.isEmpty)
        let broken = Data(#"{"id":"x","panes":[{"role":"lecture"}],"shares":[0.5,0.5]}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(PanePreset.self, from: broken) }
    }

    @Test func aClassStartsOnlyInALayoutWithItsLectureOrNote() {
        #expect(PanePreset.builtIn.allSatisfy { $0.opensClass })
        #expect(!PanePreset(name: "성적", slots: [.link(.place(.grades)), .role(.quiz)], shares: [0.5, 0.5]).opensClass)
    }

    @Test func aClassWithoutItsLectureOrNoteStartsThePlainWay() throws {
        let course = UUID(), lecture = AppLink(.material, UUID()), note = AppLink(.note, UUID())
        let quiz = AppLink.course(course, page: .quiz)
        let concepts = PanePreset(name: "개념", slots: [.role(.lecture), .role(.quiz)], shares: [0.6, 0.4])
        // A lecture and the quiz with no lecture: the quiz alone is no class's tab.
        #expect(concepts.startLayout([.quiz: [quiz], .classNote: [note]], limit: 3) == nil)
        let mine = PanePreset(name: "성적과 노트", slots: [.link(.place(.grades)), .role(.classNote)], shares: [0.3, 0.7])
        #expect(mine.startLayout([.quiz: [quiz]], limit: 3) == nil)
        let opened = try #require(mine.startLayout([.classNote: [note]], limit: 3))
        #expect(opened.links == [.place(.grades), note])
        #expect(opened.focus == 1)
        #expect(concepts.startLayout([.lecture: [lecture], .quiz: [quiz]], limit: 3)?.links == [lecture, quiz])
    }

    @Test func aFreeNameCountsUp() {
        #expect(PanePreset.freeName("내 배치", taken: []) == "내 배치")
        #expect(PanePreset.freeName("내 배치", taken: ["내 배치", "내 배치 2"]) == "내 배치 3")
    }
}

struct PaneLessonTests {
    static let device = UUID()

    static func file(_ sessions: [Session]) -> CourseFile {
        CourseFile(course: Course(device: device, at: .init(timeIntervalSince1970: 0), title: "그래프 이론"), sessions: sessions)
    }

    static func session(day: Double, material: UUID, cancelled: Bool = false, rough: UUID? = nil) -> Session {
        let date = Date(timeIntervalSince1970: day * 86400)
        var s = Session(device: device, at: date, week: 1, date: date)
        s.materials = [SessionMaterial(materialId: material, firstPage: nil)]
        s.isCancelled = cancelled
        s.roughNoteId = rough
        return s
    }

    @Test func aNoteNamesItsClass() throws {
        let lecture = UUID(), rough = UUID()
        let first = Self.session(day: 1, material: lecture, rough: rough), later = Self.session(day: 8, material: lecture)
        let file = Self.file([first, later])
        let l = try #require(PaneLayout(links: [AppLink(.material, lecture), AppLink(.note, rough)], limit: 3))
        #expect(l.lesson(in: [file], now: .init(timeIntervalSince1970: 20 * 86400))?.session.id == first.id)
    }

    @Test func aLectureNamesTheLastClassItWasGivenInByNow() throws {
        let lecture = UUID()
        let a = Self.session(day: 1, material: lecture), b = Self.session(day: 8, material: lecture)
        let holiday = Self.session(day: 10, material: lecture, cancelled: true), c = Self.session(day: 15, material: lecture)
        let file = Self.file([c, a, holiday, b])
        let l = PaneLayout(AppLink(.material, lecture, anchor: .page(3)))
        #expect(l.lesson(in: [file], now: .init(timeIntervalSince1970: 11 * 86400))?.session.id == b.id)
        // Before any, the first to come.
        #expect(l.lesson(in: [file], now: .init(timeIntervalSince1970: 0))?.session.id == a.id)
        #expect(PaneLayout(.place(.grades)).lesson(in: [file], now: .now) == nil)
    }
}

struct PaneMemoryTests {
    @Test func aNoteModeInTheSessionsLayoutComesFirst() throws {
        let session = UUID(), noteID = note.id!
        var memory = PaneMemory()
        #expect(memory.noteMode(note: noteID, session: session) == nil)
        memory.remember(.write, note: noteID, at: Date(timeIntervalSince1970: 0))
        #expect(memory.noteMode(note: noteID, session: session) == .write)

        let json = #"{"panes":[{"link":"\#(lecture.string)","share":1,"pressed":0},{"link":"\#(note.string)","share":1,"pressed":1,"noteMode":"read"}],"focus":1}"#
        let layout = try JSONDecoder().decode(PaneLayout.self, from: Data(json.utf8))
        memory.remember(layout, session: session, at: Date(timeIntervalSince1970: 1))
        #expect(memory.noteMode(note: noteID, session: session) == .read)
        #expect(memory.noteMode(note: noteID) == .write)
        #expect(memory.layout(session: session) == layout)
    }

    @Test func openingTheNoteBringsBackTheSessionsLayout() throws {
        let session = UUID()
        var memory = PaneMemory()
        var left = try #require(PaneLayout(links: [lecture, note, quiz], shares: [0.5, 0.3, 0.2], limit: 3))
        left.show(.read, in: 1)
        left.press(2)
        memory.remember(left, session: session, at: Date(timeIntervalSince1970: 0))

        let heading = note.with(.heading("Hall"))
        let restored = try #require(memory.restoring(heading, session: session, limit: 3))
        #expect(restored.links == [lecture, heading, quiz] && restored.focus == 1)
        #expect(restored.focused.noteMode == .read)
        #expect(zip(restored.shares, [0.5, 0.3, 0.2]).allSatisfy { approx($0, $1) })

        // A note the layout doesn't show, a session with none remembered: nothing to bring back.
        #expect(memory.restoring(other, session: session, limit: 3) == nil)
        #expect(memory.restoring(note, session: UUID(), limit: 3) == nil)
        // An iPad keeps the two pressed most recently, the note among them.
        let pad = try #require(memory.restoring(note, session: session, limit: 2))
        #expect(pad.links == [note, quiz] && pad.focus == 0)
    }

    @Test func aLayoutOfOnePaneIsNothingToBringBack() {
        let session = UUID()
        var memory = PaneMemory()
        memory.remember(PaneLayout(note), session: session, at: Date(timeIntervalSince1970: 0))
        #expect(memory.restoring(note, session: session, limit: 3) == nil)
        #expect(memory.layout(session: session, limit: 3) == nil)
        memory.remember(PaneLayout(links: [lecture, note], limit: 3)!, session: session, at: Date(timeIntervalSince1970: 1))
        #expect(memory.layout(session: session, limit: 3)?.links == [lecture, note])
        #expect(memory.layout(session: session, limit: 1) == nil)
    }

    @Test func forgetsWhatWasUsedLongestAgo() throws {
        var memory = PaneMemory()
        let first = UUID()
        memory.remember(.read, note: first, at: Date(timeIntervalSince1970: 0))
        for i in 1...PaneMemory.capacity { memory.remember(.split, note: UUID(), at: Date(timeIntervalSince1970: Double(i))) }
        #expect(memory.count.noteModes == PaneMemory.capacity)
        #expect(memory.noteMode(note: first) == nil)
        let back = try JSONDecoder().decode(PaneMemory.self, from: JSONEncoder().encode(memory))
        #expect(back == memory)
    }
}

/// What a layout keeps whatever is done to it, and what folding keeps at any width.
struct PaneLayoutPropertyTests {
    static let links = [lecture, note, quiz, other, AppLink(.exam, UUID()), AppLink.place(.today)]
    // An action, which pane or link, and a fraction for a drag.
    static let steps = zip(Gen.int(in: 0...7), Gen.int(in: 0...5), Gen.double(in: -0.5...1.5)).array(of: 0...30)

    static func run(_ steps: [(Int, Int, Double)], limit: Int) -> PaneLayout {
        var l = PaneLayout(links[0])
        for (action, k, x) in steps {
            switch action {
            case 0: l.openBeside(links[k], limit: limit)
            case 1: l.press(k % l.panes.count)
            case 2: l.close(k % l.panes.count)
            case 3: l.swap(k % l.panes.count, (k + 1) % l.panes.count)
            case 4: l.resize(divider: k % max(1, l.panes.count - 1), to: x)
            case 5: l.even()
            case 6: l.collapse(k % l.panes.count)
            default: l.open(links[k])
            }
        }
        return l
    }

    @Test func staysWhole() async {
        await propertyCheck(input: Self.steps, Gen.int(in: 2...3)) { steps, limit in
            let l = Self.run(steps, limit: limit)
            #expect((1...limit).contains(l.panes.count))
            #expect(l.panes.indices.contains(l.focus))
            #expect(approx(l.shares.reduce(0, +), 1))
            #expect(l.shares.allSatisfy { $0 > 0 })
            #expect(!l.collapsed.contains(l.focus))
        }
    }

    @Test func mergingKeepsBothWholeOrChangesNothing() async {
        await propertyCheck(input: Self.steps, Self.steps, Gen.int(in: 0...3)) { a, b, at in
            var l = Self.run(a, limit: 3)
            let other = Self.run(b, limit: 2)
            let before = l
            let joined = l.merge(other, at: at, limit: 3)
            #expect(joined == (before.panes.count + other.panes.count <= 3))
            guard joined else {
                #expect(l == before)
                return
            }
            #expect(l.panes.count == before.panes.count + other.panes.count)
            #expect(approx(l.shares.reduce(0, +), 1) && l.shares.allSatisfy { $0 > 0 })
            #expect(l.focused.link == other.focused.link && !l.collapsed.contains(l.focus))
            let start = min(at, before.panes.count)
            #expect(Array(l.links[start..<(start + other.panes.count)]) == other.links)
        }
    }

    @Test func foldingKeepsTheFocusOpenAndFillsTheRoom() async {
        await propertyCheck(input: Self.steps, Gen.double(in: 100...2000), Gen.double(in: 0...600)) { steps, room, more in
            let l = Self.run(steps, limit: 3)
            let (min, strip, gap) = (360.0, 40.0, 8.0)
            let f = l.fit(room: room, minWidth: min, strip: strip, gap: gap)
            let n = Double(l.panes.count)
            #expect(!f.folded.contains(l.focus))
            #expect(f.folded.count < l.panes.count)
            if f.folded.count < l.panes.count - 1 {
                #expect(l.panes.indices.filter { !f.folded.contains($0) }.allSatisfy { f.widths[$0] >= min - 1e-9 })
            }
            if room >= min + (n - 1) * (strip + gap) {
                #expect(abs(f.widths.reduce(0, +) + (n - 1) * gap - room) < 1e-6)
            }
            // A wider window never folds more.
            #expect(l.fit(room: room + more, minWidth: min, strip: strip, gap: gap).folded.count <= f.folded.count)
        }
    }

    @Test func pressingAStripUnfoldsIt() async {
        await propertyCheck(input: Self.steps, Gen.double(in: 400...1200), Gen.int(in: 0...2)) { steps, room, k in
            var l = Self.run(steps, limit: 3)
            let before = l.fit(room: room, minWidth: 360, strip: 40, gap: 8).folded
            guard let strip = before.sorted().dropFirst(k % max(1, before.count)).first else { return }
            let byHand = l.collapsed.contains(strip)
            l.press(strip)
            let after = l.fit(room: room, minWidth: 360, strip: 40, gap: 8).folded
            #expect(!after.contains(strip))
            // A strip the room folded trades places with another; one folded by hand may find room of its own.
            #expect(byHand ? after.count <= before.count : after.count == before.count)
        }
    }
}
