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
        #expect(l.shares == [0.55, 0.45] && l.focus == 0)
    }

    @Test func rolesWithNothingAreLeftOut() throws {
        let l = try #require(PanePreset.review.layout(session: Self.session(), course: Self.course, limit: 2))
        #expect(l.links == [.course(Self.course, page: .quiz)] && l.shares == [1])
        #expect(PanePreset.problems.layout(session: Self.session(), course: Self.course, limit: 2) == nil)
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

    @Test func builtInIDsAreUnique() {
        #expect(Set(PanePreset.builtIn.map(\.id)).count == PanePreset.builtIn.count)
        #expect(PanePreset.builtIn.allSatisfy { $0.roles.count == $0.shares.count })
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
    static let steps = zip(Gen.int(in: 0...6), Gen.int(in: 0...5), Gen.double(in: -0.5...1.5)).array(of: 0...30)

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
            l.press(strip)
            let after = l.fit(room: room, minWidth: 360, strip: 40, gap: 8).folded
            #expect(!after.contains(strip))
            #expect(after.count == before.count)
        }
    }
}
