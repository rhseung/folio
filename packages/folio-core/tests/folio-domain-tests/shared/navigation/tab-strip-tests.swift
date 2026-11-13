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
    /// A tab in front of one pane, 300 wide with its close button.
    let lone = TabFit.Front(trail: 260, chrome: 40)

    func singles(_ widths: [Double]) -> [TabFit.Other] { widths.map { TabFit.Other(single: $0, icon: 32) } }

    func layout(_ room: Double, front: TabFit.Front? = nil, others: [Double]) -> TabFit.Layout {
        TabFit.layout(room: room, front: front ?? lone, others: singles(others), gap: 8, more: 80)
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
        #expect(
            layout(430, others: [100, 100, 100, 100])
                == TabFit.Layout(iconsOnly: true, stacked: true, compactFront: true, shown: 1, hidden: 3))
        // Not even one icon: the menu alone, and the tab in front folds its own trail.
        #expect(layout(200, others: [100, 100]) == TabFit.Layout(iconsOnly: true, stacked: true, compactFront: true, shown: 0, hidden: 2))
    }

    @Test func givesWayInTheOrderTheUserPicked() {
        // The tab in front has two other panes: named, its capsule is 500 wide; as icons, 420. One other tab has
        // two panes (150 with its preset's name, 70 as icons, 50 stacked), one has one (100, or its 32 icon).
        let front = TabFit.Front(trail: 300, chrome: 200, compactChrome: 120)
        let others = [TabFit.Other(full: 150, icons: 70, stacked: 50), TabFit.Other(single: 100, icon: 32)]
        func step(_ room: Double) -> Int { TabFit.layout(room: room, front: front, others: others, gap: 8, more: 80).step }

        // All of it: 500 + 150 + 100 + 2 gaps.
        #expect(step(766) == 0)

        // ① names go: 500 + 70 + 32 + 16.
        #expect(step(765) == 1 && step(618) == 1)

        // ② the other tab of two panes stacks: 500 + 50 + 32 + 16.
        #expect(step(617) == 2 && step(598) == 2)

        // ③ the tab in front's other segments go to icons: 420 + 50 + 32 + 16.
        #expect(step(597) == 3 && step(518) == 3)

        // ④ the menu: alone beside the tab in front, 420 + 80 + 8.
        let menu = TabFit.layout(room: 517, front: front, others: others, gap: 8, more: 80)
        #expect(menu.step == 4 && menu.shown == 0 && menu.hidden == 2)

        // ⑤ the trail folds: 400 - 88 - 120 leaves it 192 of its 300.
        let fit = TabFit.layout(room: 400, front: front, others: others, gap: 8, more: 80)
        #expect(TabFit.trail(room: 400, front: front, others: others, layout: fit, gap: 8, more: 80) == 192)
        #expect(TabFit.trail(room: 517, front: front, others: others, layout: menu, gap: 8, more: 80) == nil)
    }

    /// Others whose stacked form is no wider than their icons, and those no wider than their names.
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

    func trail(_ room: Double, front: TabFit.Front? = nil, others: [Double]) -> Double? {
        let fit = layout(room, front: front, others: others)
        return TabFit.trail(room: room, front: front ?? lone, others: singles(others), layout: fit, gap: 8, more: 80)
    }

    @Test func theFrontTrailIsFreeWhileItFits() {
        // Room to spare at any width: nothing the window's width changes, so a resize there redraws nothing.
        #expect(trail(516, others: [100, 100]) == nil)
        #expect(trail(2000, others: [100, 100]) == nil)
        // Icons only, 300 + 32 + 32 + 2 gaps = 380 still fits.
        #expect(trail(380, others: [100, 100]) == nil)
    }

    @Test func theFrontTrailIsHeldWhenTheRowRunsOut() {
        // The menu alone at 200: 200 - (80 + 8) - 40 = 72, however short, so the strip stays inside the row.
        #expect(trail(200, others: [100, 100]) == 72)
        // A front tab of 400 (a trail of 360) beside one icon in 460: 460 - 32 - 8 - 40 = 380 still holds it.
        let long = TabFit.Front(trail: 360, chrome: 40)
        #expect(trail(460, front: long, others: [100]) == nil)
        // In 400 the other tab goes to the menu: 400 - (80 + 8) - 40 = 272 for a trail that needs 360.
        #expect(trail(400, front: long, others: [100]) == 272)
    }

    @Test func theNewTabGlyphSitsOneGapAfterTheLastCapsule() {
        // A 12-point plus centered in a 32-point button has 10 on each side: the button starts 2 under the capsule.
        #expect(TabFit.newTabSpacing(gap: 8, button: 32, glyph: 12) == -2)
        #expect(TabFit.newTabSpacing(gap: 8, button: 32, glyph: 16) == 0)
        // The glyph's own start, wherever the button puts it.
        for glyph in stride(from: 8.0, through: 32, by: 2) {
            let spacing = TabFit.newTabSpacing(gap: 8, button: 32, glyph: glyph)
            #expect(spacing + (32 - glyph) / 2 == 8)
        }
    }

    @Test func theStripNeverOutgrowsTheRow() async {
        // Wider than the row, the strip pushes the toolbar's search field and buttons into its overflow menu (#310).
        // It may only when not even the front tab's capsule and the menu fit.
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

        // By hand: the menu alone beside a front tab held to 200 - 88 - 40 = 72, which with its capsule fills the row.
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
            // Over only when the tab in front, with the menu, already is.
            #expect(used <= Double(room) || fit.shown == 0)
            if menu {
                // One more tab would not have fit.
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
        // "a" was dropped; the policy has room for it, but it comes back only when it is in front.
        let left = ["a": now - 5, "b": now - 10]
        #expect(TabKeep.alive(selected: "c", alive: ["b", "c"], left: left, now: now, policy: policy) == ["b", "c"])
        #expect(TabKeep.alive(selected: "a", alive: ["b", "c"], left: left, now: now, policy: policy) == ["a", "b", "c"])
    }

    @Test func memoryPressureKeepsOnlyTheFront() {
        let left = ["a": now - 1, "b": now - 2]
        #expect(TabKeep.alive(selected: "c", alive: ["a", "b", "c"], left: left, now: now, policy: policy, pressure: true) == ["c"])
    }

    /// A tab playing a recording stays past the limit, the idle time and memory pressure, and takes no other tab's room.
    @Test func aPlayingTabIsNeverDropped() {
        let left = ["a": now - 30, "b": now - 10, "c": now - 20, "p": now - 9_000]
        let kept = TabKeep.alive(selected: "d", alive: ["a", "b", "c", "d", "p"], left: left, now: now, policy: policy, playing: ["p"])
        #expect(kept == ["d", "b", "c", "p"])
        #expect(
            TabKeep.alive(selected: "d", alive: ["a", "d", "p"], left: left, now: now, policy: policy, pressure: true, playing: ["p"]) == [
                "d", "p",
            ])
        // Playing doesn't bring back a tab already dropped: its screen, and so its audio, is gone.
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

            // Nothing kept is older than something dropped that was within the time.
            let dropped = alive.subtracting(kept).filter { now.timeIntervalSince(left[$0]!) < 500 }
            if !pressure, let oldestKept = kept.subtracting(held).map({ left[$0]! }).min(),
                let newestDropped = dropped.map({ left[$0]! }).max()
            {
                #expect(oldestKept >= newestDropped)
            }
        }
    }
}
