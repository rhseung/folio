import FolioDomain
import Foundation
import PropertyBased
import Testing

struct TabStripTests {
    @Test func aNewTabGoesLastAndComesForward() {
        var s = TabStrip("a")
        s.open("b")
        s.select("a")
        s.open("c")
        #expect(s.tabs == ["a", "b", "c"] && s.selected == "c")
        s.open("a")
        #expect(s.tabs == ["a", "b", "c"] && s.selected == "a")
    }

    @Test func aTabFromALinkGoesBesideTheOneItCameFrom() {
        var s = TabStrip("a")
        for t in ["b", "c"] { s.open(t) }
        s.select("a")
        s.open("d", afterSelected: true)

        #expect(s.tabs == ["a", "d", "b", "c"] && s.selected == "d")

        s.open("e", afterSelected: true)
        #expect(s.tabs == ["a", "d", "e", "b", "c"])

        s.select("c")
        s.open("f", afterSelected: true)
        #expect(s.tabs.last == "f")
    }

    @Test func closingTheTabInFrontBringsTheNextOne() {
        var s = TabStrip("a")
        for t in ["b", "c", "d"] { s.open(t) }
        s.select("b")
        let first = s.close("b")

        #expect(first)
        #expect(s.tabs == ["a", "c", "d"] && s.selected == "c")

        s.select("d")
        let last = s.close("d")
        #expect(last)
        #expect(s.selected == "c")

        let behind = s.close("a")
        #expect(behind)
        #expect(s.tabs == ["c"] && s.selected == "c")
    }

    @Test func theLastTabStays() {
        var s = TabStrip("a")
        let alone = s.close("a")
        #expect(!alone)
        #expect(s.tabs == ["a"])
        let missing = s.close("x")
        #expect(!missing)
    }

    @Test func closesTheOthers() {
        var s = TabStrip("a")
        for t in ["b", "c"] { s.open(t) }
        s.closeOthers(than: "b")
        #expect(s.tabs == ["b"] && s.selected == "b")
    }

    @Test func stepsAroundAndByNumber() {
        var s = TabStrip("a")
        for t in ["b", "c"] { s.open(t) }
        s.selectNext()

        #expect(s.selected == "a")
        s.selectPrevious()
        #expect(s.selected == "c")
        s.select(number: 2)
        #expect(s.selected == "b")
        s.select(number: 8)
        #expect(s.selected == "b")
        s.select(number: 0)
        #expect(s.selected == "b")

        s.select(number: 9)
        #expect(s.selected == "c")

        for t in 3...11 { s.open("\(t)") }
        s.select(number: 1)
        s.select(number: 9)
        #expect(s.selected == "11")
    }

    @Test func movesATab() {
        var s = TabStrip("a")
        for t in ["b", "c", "d"] { s.open(t) }
        s.move("d", to: 0)
        #expect(s.tabs == ["d", "a", "b", "c"] && s.selected == "d")
        s.move("a", to: 99)
        #expect(s.tabs == ["d", "b", "c", "a"])
    }

    @Test func aTabFromAnotherWindowLandsWhereItWasDropped() {
        var s = TabStrip("a")
        s.open("b")
        s.select("a")
        s.insert("x", at: 1)
        #expect(s.tabs == ["a", "x", "b"] && s.selected == "x")
        s.insert("y", at: 99)
        #expect(s.tabs == ["a", "x", "b", "y"])
        s.insert("z", at: -3)
        #expect(s.tabs == ["z", "a", "x", "b", "y"])
        s.insert("a", at: 3)
        #expect(s.tabs == ["z", "a", "x", "b", "y"] && s.selected == "a")
    }

    @Test func restoresOnlyAWholeStrip() {
        #expect(TabStrip(tabs: ["a", "b"], selected: "b")?.selectedIndex == 1)
        #expect(TabStrip(tabs: ["a", "b"], selected: "c") == nil)
        #expect(TabStrip(tabs: ["a", "a"], selected: "a") == nil)
    }

    @Test func alwaysHoldsTheTabInFrontOnce() async {
        await propertyCheck(input: Gen.int(in: 0...5).array(of: 0...40), Gen.int(in: 0...9)) { ops, k in
            var s = TabStrip(0)
            var next = 1
            for op in ops {
                let some = s.tabs[k % s.tabs.count]
                switch op {
                case 0:
                    s.open(next, afterSelected: k % 2 == 0)
                    next += 1
                case 1: s.close(some)
                case 2: s.selectNext()
                case 3: s.move(some, to: k)
                case 4: s.select(number: k)
                default: s.select(some)
                }
                #expect(s.tabs.contains(s.selected))
                #expect(Set(s.tabs).count == s.tabs.count)
            }
        }
    }
}

struct TabFitTests {
    // 시안의 1440 창이다. 탭 줄은 새 탭 + 앞까지 904이고, 오늘은 아이콘만 보이는 32 폭이다.
    let bounds = TabFit.Bounds(min: 120, max: 280, grid: 4)
    let today = TabFit.Tab.fixed(32)

    func layout(_ room: Double, front: TabFit.Tab = .single, others: [TabFit.Tab]) -> TabFit.Layout {
        TabFit.layout(room: room, front: front, others: others, gap: 8, more: 40, bounds: bounds)
    }

    func named(_ n: Int) -> [TabFit.Tab] { Array(repeating: .single, count: n) }

    @Test func fewTabsStopAtTheWidest() {
        // 904 - 32 - 간격 2개 = 856을 둘이 나누면 428이라 280에 묶인다.
        #expect(layout(904, others: [today, .single]) == TabFit.Layout(share: 280, shown: 2, hidden: 0))
    }

    @Test func moreTabsShareTheRow() {
        // 904 - 32 - 간격 5개 = 832를 다섯이 나누면 166.4이고, 4의 배수로 내려 164다.
        #expect(layout(904, others: [today] + named(4)) == TabFit.Layout(share: 164, shown: 5, hidden: 0))
    }

    @Test func tabsNarrowerThanTheLeastGoToTheMenu() {
        // 아홉이 나누면 88이다. 셋을 메뉴로 보내면 904 - 32 - 간격 6개 - (8 + 40) = 776을 여섯이 나눠 128이 된다.
        #expect(layout(904, others: [today] + named(8)) == TabFit.Layout(share: 128, shown: 6, hidden: 3))
    }

    @Test func todayStaysOutOfTheDivision() {
        let withToday = layout(600, others: [today, .single])
        let without = layout(600 - 32 - 8, others: [.single])
        #expect(withToday.share == without.share)
    }

    @Test func aJoinedFrontTakesAShareForEachPane() {
        // 칸이 셋인 고른 탭과 다른 탭 하나가 넷으로 나눈다. 904 - 8 = 896을 넷이 나누면 224다.
        let fit = layout(904, front: .shares(3), others: [.single])
        #expect(fit == TabFit.Layout(share: 224, shown: 1, hidden: 0))
        #expect(TabFit.width(front: .shares(3), others: [.single], layout: fit, gap: 8, more: 40) == 904)
    }

    @Test func aLoneFrontShrinksBelowTheLeastRatherThanOverflow() {
        #expect(layout(100, others: []) == TabFit.Layout(share: 100, shown: 0, hidden: 0))
        // 다른 탭이 모두 메뉴로 가면 90 - (8 + 40) = 42가 남는다.
        #expect(layout(90, others: named(2)) == TabFit.Layout(share: 40, shown: 0, hidden: 2))
    }

    @Test func anIconFrontLeavesTheRowToTheOthers() {
        #expect(layout(904, front: today, others: named(2)) == TabFit.Layout(share: 280, shown: 2, hidden: 0))
        #expect(layout(20, front: today, others: []) == TabFit.Layout(share: 0, shown: 0, hidden: 0))
    }

    static let tabs = Gen.int(in: 0...4).map { n -> TabFit.Tab in
        switch n {
        case 0: .fixed(32)
        case 1: .fixed(90)
        case 2: .shares(2)
        default: .single
        }
    }.array(of: 0...12)

    @Test func shownTabsFitBetweenTheBounds() async {
        await propertyCheck(input: Self.tabs, Self.tabs, Gen.int(in: 0...2400)) { fronts, others, room in
            let front = fronts.first ?? .single
            let fit = layout(Double(room), front: front, others: others)
            #expect(fit.shown + fit.hidden == others.count)
            if fit.shown > 0 {
                #expect(fit.share >= 120 || ([front] + others.prefix(fit.shown)).allSatisfy { $0.shareCount == 0 })
                #expect(TabFit.width(front: front, others: others, layout: fit, gap: 8, more: 40) <= Double(room))
            }
            #expect(fit.share <= 280 && fit.share.truncatingRemainder(dividingBy: 4) == 0)
        }
    }

    @Test func noMoreIsHiddenThanNeeded() async {
        await propertyCheck(input: Self.tabs, Gen.int(in: 0...2400)) { others, room in
            let fit = layout(Double(room), others: others)
            guard fit.hidden > 0 else { return }
            let one = TabFit.Layout(share: 120, shown: fit.shown + 1, hidden: fit.hidden - 1)
            #expect(TabFit.width(front: .single, others: others, layout: one, gap: 8, more: 40) > Double(room))
        }
    }

    @Test func aNarrowerRowNeverShowsMore() async {
        await propertyCheck(input: Self.tabs, Gen.int(in: 0...2400), Gen.int(in: 1...400)) { others, room, less in
            let wide = layout(Double(room), others: others)
            let narrow = layout(Double(room - less), others: others)
            #expect(narrow.shown <= wide.shown)
            if narrow.shown == wide.shown { #expect(narrow.share <= wide.share) }
        }
    }

    @Test func theFirstTabLinesUpWithThePanelEdge() async {
        await propertyCheck(input: Gen.int(in: 0...300), Gen.int(in: 0...400)) { after, edge in
            let start = Double(after) + TabFit.lead(panelEdge: Double(edge), after: Double(after), gap: 8)
            if Double(edge - after) >= 8 {
                #expect(start == Double(edge))
            } else {
                #expect(start == Double(after) + 8)
            }
        }

        #expect(TabFit.lead(panelEdge: 216, after: 189, gap: 8) == 27)

        #expect(TabFit.lead(panelEdge: 4, after: 189, gap: 8) == 8)
    }

    @Test func panesShowNamesOnlyWhenTwoHaveRoom() {
        #expect(TabFit.namesPanes(2, width: 280, least: 72))
        #expect(!TabFit.namesPanes(2, width: 132, least: 72))
        #expect(!TabFit.namesPanes(3, width: 280, least: 72))
        #expect(!TabFit.namesPanes(4, width: 1000, least: 72))
    }

    @Test func aShortPaneLeavesItsRoomToALongOne() {
        #expect(TabFit.split(240, ideals: [60, 200]) == [60, 180])
        #expect(TabFit.split(300, ideals: [60, 200]) == [80, 220])
        #expect(TabFit.split(240, ideals: [200, 200]) == [120, 120])
        #expect(TabFit.split(300, ideals: [40, 200, 200]) == [40, 130, 130])
    }

    @Test func panesFillTheTabAndNeverTakeMoreThanTheyNeedWhenCramped() async {
        let ideals = Gen.int(in: 0...300).map(Double.init).array(of: 1...4)
        await propertyCheck(input: ideals, Gen.int(in: 0...800)) { ideals, room in
            let widths = TabFit.split(Double(room), ideals: ideals)
            #expect(abs(widths.reduce(0, +) - Double(room)) < 0.001)
            if ideals.reduce(0, +) > Double(room) {
                #expect(zip(widths, ideals).allSatisfy { $0 <= $1 + 0.001 })
            }
        }
    }

    @Test func theNewTabGlyphSitsOneGapAfterTheLastCapsule() {
        // 32pt 버튼 가운데에 놓인 12pt의 +는 양쪽에 10씩 남으므로, 버튼은 capsule보다 2만큼 앞에서 시작한다.
        #expect(TabFit.newTabSpacing(gap: 8, button: 32, glyph: 12) == -2)
        #expect(TabFit.newTabSpacing(gap: 8, button: 32, glyph: 16) == 0)
        for glyph in stride(from: 8.0, through: 32, by: 2) {
            let spacing = TabFit.newTabSpacing(gap: 8, button: 32, glyph: glyph)
            #expect(spacing + (32 - glyph) / 2 == 8)
        }
    }
}

struct TabKeepTests {
    let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
    let policy = TabKeep.Policy(limit: 2, idle: 600)

    @Test func keepsTheMostRecentTabsBehindTheFront() {
        let left = ["a": now - 30, "b": now - 10, "c": now - 20]
        let kept = TabKeep.alive(selected: "d", alive: ["a", "b", "c", "d"], left: left, now: now, policy: policy)
        #expect(kept == ["d", "b", "c"])
    }

    @Test func dropsATabBehindForTooLong() {
        let left = ["a": now - 601, "b": now - 599]
        #expect(TabKeep.alive(selected: "c", alive: ["a", "b", "c"], left: left, now: now, policy: policy) == ["b", "c"])
    }

    @Test func aDroppedTabStaysDroppedUntilInFront() {
        let left = ["a": now - 5, "b": now - 10]
        #expect(TabKeep.alive(selected: "c", alive: ["b", "c"], left: left, now: now, policy: policy) == ["b", "c"])
        #expect(TabKeep.alive(selected: "a", alive: ["b", "c"], left: left, now: now, policy: policy) == ["a", "b", "c"])
    }

    @Test func memoryPressureKeepsOnlyTheFront() {
        let left = ["a": now - 1, "b": now - 2]
        #expect(TabKeep.alive(selected: "c", alive: ["a", "b", "c"], left: left, now: now, policy: policy, pressure: true) == ["c"])
    }

    @Test func aPlayingTabIsNeverDropped() {
        let left = ["a": now - 30, "b": now - 10, "c": now - 20, "p": now - 9_000]
        let kept = TabKeep.alive(selected: "d", alive: ["a", "b", "c", "d", "p"], left: left, now: now, policy: policy, playing: ["p"])
        #expect(kept == ["d", "b", "c", "p"])
        #expect(
            TabKeep.alive(selected: "d", alive: ["a", "d", "p"], left: left, now: now, policy: policy, pressure: true, playing: ["p"]) == [
                "d", "p",
            ])
        #expect(TabKeep.alive(selected: "d", alive: ["d"], left: left, now: now, policy: policy, playing: ["p"]) == ["d"])
    }

    @Test func aTabWithoutATimeCountsAsJustLeft() {
        #expect(TabKeep.alive(selected: "b", alive: ["a", "b"], left: [:], now: now, policy: policy) == ["a", "b"])
    }

    @Test func holdsItsBounds() async {
        await propertyCheck(
            input: Gen.int(in: 0...9).array(of: 0...12), Gen.int(in: 0...12), Gen.int(in: 0...4), Gen.bool,
            Gen.int(in: 0...12).array(of: 0...3)
        ) { ages, selected, limit, pressure, played in
            let left = Dictionary(uniqueKeysWithValues: ages.enumerated().map { ($0.offset, now - Double($0.element) * 100) })
            let alive = Set(left.keys)
            let p = TabKeep.Policy(limit: limit, idle: 500)
            let playing = Set(played)
            let kept = TabKeep.alive(
                selected: selected, alive: alive, left: left, now: now, policy: p, pressure: pressure, playing: playing)

            let held = playing.intersection(alive).union([selected])
            #expect(held.isSubset(of: kept))
            #expect(kept.subtracting([selected]).isSubset(of: alive))
            #expect(kept.subtracting(held).count <= (pressure ? 0 : limit))
            for id in kept.subtracting(held) { #expect(now.timeIntervalSince(left[id]!) < 500) }

            let dropped = alive.subtracting(kept).filter { now.timeIntervalSince(left[$0]!) < 500 }
            if !pressure, let oldestKept = kept.subtracting(held).map({ left[$0]! }).min(),
                let newestDropped = dropped.map({ left[$0]! }).max()
            {
                #expect(oldestKept >= newestDropped)
            }
        }
    }
}

struct TabStripBehindTests {
    @Test func tabsOpenedBehindLineUpAfterTheTabTheyCameFrom() {
        var s = TabStrip("a")
        s.open("b")
        s.select("a")
        s.openBehind("c")
        s.openBehind("d")
        #expect(s.tabs == ["a", "c", "d", "b"] && s.selected == "a")

        s.select("b")
        s.openBehind("e")
        #expect(s.tabs == ["a", "c", "d", "b", "e"] && s.selected == "b")

        s.select("a")
        s.openBehind("f")
        #expect(s.tabs == ["a", "f", "c", "d", "b", "e"])
    }

    @Test func aTabAlreadyOpenIsNotOpenedAgainBehind() {
        var s = TabStrip("a")
        s.open("b")
        s.openBehind("a")
        #expect(s.tabs == ["a", "b"] && s.selected == "b")
    }
}
