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
    let lone = TabFit.Front(trail: 260, chrome: 40)

    func singles(_ widths: [Double]) -> [TabFit.Other] { widths.map { TabFit.Other(single: $0, icon: 32) } }

    func layout(_ room: Double, front: TabFit.Front? = nil, others: [Double]) -> TabFit.Layout {
        TabFit.layout(room: room, front: front ?? lone, others: singles(others), gap: 8, more: 80)
    }

    @Test func roomyRowShowsNames() {
        // 300 + 100 + 100 + 간격 2개 = 516이다.
        #expect(layout(516, others: [100, 100]) == TabFit.Layout(iconsOnly: false, shown: 2, hidden: 0))
    }

    @Test func tightRowShowsIconsFirst() {
        // 이름은 들어가지 않고 아이콘은 들어간다. 300 + 32 + 32 + 간격 2개 = 380이다.
        #expect(layout(515, others: [100, 100]) == TabFit.Layout(iconsOnly: true, shown: 2, hidden: 0))
        #expect(layout(380, others: [100, 100]) == TabFit.Layout(iconsOnly: true, shown: 2, hidden: 0))
    }

    @Test func thenFoldsTheRestIntoTheMenu() {
        // 아이콘 네 개에는 460이 필요하고, 아이콘 하나와 메뉴와 간격 2개에는 428이 필요하다.
        #expect(
            layout(430, others: [100, 100, 100, 100])
                == TabFit.Layout(iconsOnly: true, stacked: true, compactFront: true, shown: 1, hidden: 3))
        #expect(layout(200, others: [100, 100]) == TabFit.Layout(iconsOnly: true, stacked: true, compactFront: true, shown: 0, hidden: 2))
    }

    @Test func givesWayInTheOrderTheUserPicked() {
        // 앞의 탭에는 다른 칸이 둘 있어서, 이름을 보이면 capsule의 폭이 500이고 아이콘으로는 420이다. 다른 탭 하나는 칸이 둘이고(배치 이름으로 150, 아이콘으로 70, 겹치면 50),
        // 다른 하나는 칸이 하나다(100, 아이콘이면 32).
        let front = TabFit.Front(trail: 300, chrome: 200, compactChrome: 120)
        let others = [TabFit.Other(full: 150, icons: 70, stacked: 50), TabFit.Other(single: 100, icon: 32)]
        func step(_ room: Double) -> Int { TabFit.layout(room: room, front: front, others: others, gap: 8, more: 80).step }

        // 모두 보이면 500 + 150 + 100 + 간격 2개이다.
        #expect(step(766) == 0)

        // ① 이름이 빠지면 500 + 70 + 32 + 16이다.
        #expect(step(765) == 1 && step(618) == 1)

        // ② 칸이 둘인 다른 탭이 겹치면 500 + 50 + 32 + 16이다.
        #expect(step(617) == 2 && step(598) == 2)

        // ③ 앞의 탭의 다른 구획이 아이콘이 되면 420 + 50 + 32 + 16이다.
        #expect(step(597) == 3 && step(518) == 3)

        // ④ 앞의 탭 옆에 메뉴만 남으면 420 + 80 + 8이다.
        let menu = TabFit.layout(room: 517, front: front, others: others, gap: 8, more: 80)
        #expect(menu.step == 4 && menu.shown == 0 && menu.hidden == 2)

        // ⑤ 꼬리가 접히면 400 - 88 - 120이 남아, 꼬리는 300 중 192를 받는다.
        let fit = TabFit.layout(room: 400, front: front, others: others, gap: 8, more: 80)
        #expect(TabFit.trail(room: 400, front: front, others: others, layout: fit, gap: 8, more: 80) == 192)
        #expect(TabFit.trail(room: 517, front: front, others: others, layout: menu, gap: 8, more: 80) == nil)
    }

    static let others = Gen.int(in: 32...200).array(of: 3).map { w -> TabFit.Other in
        let stacked = Double(min(w[2], 60))
        let icons = max(Double(min(w[1], 120)), stacked)
        return TabFit.Other(full: max(Double(w[0]), icons), icons: icons, stacked: stacked)
    }.array(of: 0...12)

    @Test func aNarrowerRowNeverTakesAStepBack() async {
        await propertyCheck(input: Self.others, Gen.int(in: 0...2000), Gen.int(in: 1...400), Gen.int(in: 60...400), Gen.int(in: 0...200)) {
            others, room, less, trail, extra in
            let front = TabFit.Front(trail: Double(trail), chrome: 40 + Double(extra), compactChrome: 40 + Double(extra / 2))
            let wide = TabFit.layout(room: Double(room), front: front, others: others, gap: 8, more: 80)
            let narrow = TabFit.layout(room: Double(room - less), front: front, others: others, gap: 8, more: 80)
            #expect(narrow.step >= wide.step)
            #expect(narrow.shown <= wide.shown)
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

    func trail(_ room: Double, front: TabFit.Front? = nil, others: [Double]) -> Double? {
        let fit = layout(room, front: front, others: others)
        return TabFit.trail(room: room, front: front ?? lone, others: singles(others), layout: fit, gap: 8, more: 80)
    }

    @Test func theFrontTrailIsFreeWhileItFits() {
        #expect(trail(516, others: [100, 100]) == nil)
        #expect(trail(2000, others: [100, 100]) == nil)
        // 아이콘만 보이면 300 + 32 + 32 + 간격 2개 = 380이라 아직 들어간다.
        #expect(trail(380, others: [100, 100]) == nil)
    }

    @Test func theFrontTrailIsHeldWhenTheRowRunsOut() {
        // 폭 200에서 메뉴만 남으면 200 - (80 + 8) - 40 = 72이다. 아무리 짧아도 이 값을 주어야 띠가 row 안에 남는다.
        #expect(trail(200, others: [100, 100]) == 72)
        // 폭 460에서 아이콘 하나 옆의 폭 400인 앞의 탭(꼬리 360)은 460 - 32 - 8 - 40 = 380이라 아직 들어간다.
        let long = TabFit.Front(trail: 360, chrome: 40)
        #expect(trail(460, front: long, others: [100]) == nil)
        // 폭 400에서는 다른 탭이 메뉴로 가고, 360이 필요한 꼬리에 400 - (80 + 8) - 40 = 272가 남는다.
        #expect(trail(400, front: long, others: [100]) == 272)
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

    @Test func theStripNeverOutgrowsTheRow() async {
        await propertyCheck(input: Self.others, Gen.int(in: 0...2000), Gen.int(in: 20...600), Gen.int(in: 0...200)) {
            others, room, trail, extra in
            let front = TabFit.Front(trail: Double(trail), chrome: 40 + Double(extra), compactChrome: 40)
            let r = Double(room)
            let fit = TabFit.layout(room: r, front: front, others: others, gap: 8, more: 80)
            let held = TabFit.trail(room: r, front: front, others: others, layout: fit, gap: 8, more: 80)
            let width = TabFit.width(front: front, others: others, layout: fit, trail: held, gap: 8, more: 80)
            let least = front.chrome(compact: fit.compactFront) + (fit.hidden > 0 ? 88 : 0)
            #expect(width <= r || r < least)
        }

        let fit = layout(200, others: [100, 100])
        #expect(TabFit.width(front: lone, others: singles([100, 100]), layout: fit, trail: 72, gap: 8, more: 80) == 200)
    }

    @Test func aLoneTabNeverNeedsTheMenu() {
        #expect(layout(100, others: []).hidden == 0)
        #expect(layout(300, others: []) == TabFit.Layout(iconsOnly: false, shown: 0, hidden: 0))
    }

    @Test func whatIsShownFitsAndNoMoreIsHidden() async {
        await propertyCheck(input: Self.others, Gen.int(in: 100...2000), Gen.int(in: 60...600)) { others, room, selected in
            let front = TabFit.Front(trail: Double(selected) - 40, chrome: 40)
            let fit = TabFit.layout(room: Double(room), front: front, others: others, gap: 8, more: 80)
            #expect(fit.shown + fit.hidden == others.count)
            let tabs = others.prefix(fit.shown).map(fit.width(of:)).reduce(0, +)
            let menu = fit.hidden > 0
            let used = Double(selected) + tabs + (menu ? 80 : 0) + 8 * Double(fit.shown + (menu ? 1 : 0))
            #expect(used <= Double(room) || fit.shown == 0)
            if menu {
                let next = others.prefix(fit.shown + 1).map(fit.width(of:)).reduce(0, +)
                let more = Double(selected) + next + 80 + 8 * Double(fit.shown + 2)
                #expect(more > Double(room) || fit.shown + 1 == others.count)
            }
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
