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
        s.select(number: 9)
        #expect(s.selected == "b")
        s.select(number: 0)
        #expect(s.selected == "b")
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
                    s.open(next)
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

    @Test func tabsStartAtThePanelCorner() async {
        // The sidebar open: wherever the row put the buttons, the first tab starts at the trail's start.
        await propertyCheck(input: Gen.int(in: 0...180), Gen.int(in: 200...400)) { after, trailStart in
            let lead = TabFit.lead(trailStart: Double(trailStart), after: Double(after), gap: 8)
            #expect(Double(after) + lead == Double(trailStart))
        }
        // Folded, the corner is under the buttons: a gap after them.
        #expect(TabFit.lead(trailStart: 20, after: 189, gap: 8) == 8)
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
