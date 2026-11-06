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
        // Another from there goes after it in turn.
        s.open("e", afterSelected: true)
        #expect(s.tabs == ["a", "d", "e", "b", "c"])
        // From the last tab, last.
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
        // The last one hands over to the one before it.
        s.select("d")
        let last = s.close("d")
        #expect(last)
        #expect(s.selected == "c")
        // A tab behind closes without moving the front one.
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
        // ⌘9 is the last, with fewer than nine tabs or more.
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
    func layout(_ room: Double, selected: Double = 300, others: [Double]) -> TabFit.Layout {
        TabFit.layout(room: room, selected: selected, others: others, icon: 32, gap: 8, more: 80)
    }

    @Test func roomyRowShowsNames() {
        // 300 + 100 + 100 + 2 gaps = 516.
        #expect(layout(516, others: [100, 100]) == TabFit.Layout(iconsOnly: false, shown: 2, hidden: 0))
    }

    @Test func tightRowShowsIconsFirst() {
        // Names don't fit; icons do: 300 + 32 + 32 + 2 gaps = 380.
        #expect(layout(515, others: [100, 100]) == TabFit.Layout(iconsOnly: true, shown: 2, hidden: 0))
        #expect(layout(380, others: [100, 100]) == TabFit.Layout(iconsOnly: true, shown: 2, hidden: 0))
    }

    @Test func thenFoldsTheRestIntoTheMenu() {
        // Four icons need 460; one icon, the menu and 2 gaps 428.
        #expect(layout(430, others: [100, 100, 100, 100]) == TabFit.Layout(iconsOnly: true, shown: 1, hidden: 3))
        // Not even one icon: the menu alone, and the tab in front folds its own trail.
        #expect(layout(200, others: [100, 100]) == TabFit.Layout(iconsOnly: true, shown: 0, hidden: 2))
    }

    @Test func theFirstTabLinesUpWithThePanelEdge() async {
        // Wherever the row put the buttons and wherever the panel's edge is: on the edge when it leaves the gap after
        // the buttons, else the gap after them.
        await propertyCheck(input: Gen.int(in: 0...300), Gen.int(in: 0...400)) { after, edge in
            let start = Double(after) + TabFit.lead(panelEdge: Double(edge), after: Double(after), gap: 8)
            if Double(edge - after) >= 8 {
                #expect(start == Double(edge))
            } else {
                #expect(start == Double(after) + 8)
            }
        }
        // The sidebar open: the panel's edge at 216, the buttons ending at 189.
        #expect(TabFit.lead(panelEdge: 216, after: 189, gap: 8) == 27)
        // Folded, the edge is under the buttons.
        #expect(TabFit.lead(panelEdge: 4, after: 189, gap: 8) == 8)
    }

    @Test func aLoneTabNeverNeedsTheMenu() {
        #expect(layout(100, others: []) == TabFit.Layout(iconsOnly: false, shown: 0, hidden: 0))
    }

    @Test func whatIsShownFitsAndNoMoreIsHidden() async {
        await propertyCheck(input: Gen.int(in: 32...200).array(of: 0...20), Gen.int(in: 100...2000), Gen.int(in: 60...600)) { others, room, selected in
            let o = others.map(Double.init)
            let fit = TabFit.layout(room: Double(room), selected: Double(selected), others: o, icon: 32, gap: 8, more: 80)
            #expect(fit.shown + fit.hidden == o.count)
            let tabs = fit.iconsOnly ? 32 * Double(fit.shown) : o.prefix(fit.shown).reduce(0, +)
            let menu = fit.hidden > 0
            let used = Double(selected) + tabs + (menu ? 80 : 0) + 8 * Double(fit.shown + (menu ? 1 : 0))
            // Over only when the tab in front, with the menu, already is.
            #expect(used <= Double(room) || fit.shown == 0)
            if menu {
                // One more icon would not have fit.
                let more = Double(selected) + 32 * Double(fit.shown + 1) + 80 + 8 * Double(fit.shown + 2)
                #expect(more > Double(room) || fit.shown + 1 == o.count)
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
        // "a" was dropped; the policy has room for it, but it comes back only when it is in front.
        let left = ["a": now - 5, "b": now - 10]
        #expect(TabKeep.alive(selected: "c", alive: ["b", "c"], left: left, now: now, policy: policy) == ["b", "c"])
        #expect(TabKeep.alive(selected: "a", alive: ["b", "c"], left: left, now: now, policy: policy) == ["a", "b", "c"])
    }

    @Test func memoryPressureKeepsOnlyTheFront() {
        let left = ["a": now - 1, "b": now - 2]
        #expect(TabKeep.alive(selected: "c", alive: ["a", "b", "c"], left: left, now: now, policy: policy, pressure: true) == ["c"])
    }

    @Test func aTabWithoutATimeCountsAsJustLeft() {
        #expect(TabKeep.alive(selected: "b", alive: ["a", "b"], left: [:], now: now, policy: policy) == ["a", "b"])
    }

    @Test func holdsItsBounds() async {
        await propertyCheck(input: Gen.int(in: 0...9).array(of: 0...12), Gen.int(in: 0...12), Gen.int(in: 0...4), Gen.bool) { ages, selected, limit, pressure in
            let left = Dictionary(uniqueKeysWithValues: ages.enumerated().map { ($0.offset, now - Double($0.element) * 100) })
            let alive = Set(left.keys)
            let p = TabKeep.Policy(limit: limit, idle: 500)
            let kept = TabKeep.alive(selected: selected, alive: alive, left: left, now: now, policy: p, pressure: pressure)
            #expect(kept.contains(selected))
            #expect(kept.subtracting([selected]).isSubset(of: alive))
            #expect(kept.count <= (pressure ? 1 : limit + 1))
            for id in kept where id != selected { #expect(now.timeIntervalSince(left[id]!) < 500) }
            // Nothing kept is older than something dropped that was within the time.
            let dropped = alive.subtracting(kept).subtracting([selected]).filter { now.timeIntervalSince(left[$0]!) < 500 }
            if !pressure, let oldestKept = kept.subtracting([selected]).map({ left[$0]! }).min(), let newestDropped = dropped.map({ left[$0]! }).max() {
                #expect(oldestKept >= newestDropped)
            }
        }
    }
}
