import FolioDomain
import Foundation
import PropertyBased
import Testing

struct ShortcutTableTests {
    @Test func everyCommandIsRegisteredOnce() {
        let ids = ShortcutTable.standard.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(Set(ids) == Set(ShortcutID.allCases))
        #expect(ShortcutTable.standard.allSatisfy { !$0.name.isEmpty && $0.key != nil })
    }

    @Test func theStandardTableHasNoClashes() {
        #expect(ShortcutTable.clashes(in: ShortcutTable.standard).isEmpty)
    }

    @Test func choiceKeysFollowTheOptionsInOrder() {
        let keys = ShortcutTable.shortcut(.solveChoice).bindings.map(\.combo)
        #expect(keys.first == KeyCombo("1", []) && keys.last == KeyCombo("9", []) && keys.count == 9)
        #expect(!Shortcut.Scope.study.isText)
    }

    @Test func boldInANoteIsNotTheTeXBuild() {
        #expect(ShortcutTable.shortcut(.noteBold).key == ShortcutTable.shortcut(.texBuild).key)
        #expect(!Shortcut.Scope.noteEditing.overlaps(.texEditing))
    }

    @Test func anAppKeyClashesWithBoldWhileWritingANote() {
        var table = ShortcutTable.standard
        table.append(Shortcut(.search, .app, keys: [.init(KeyCombo("b"))]))
        let clashes = ShortcutTable.clashes(in: table)
        #expect(clashes.contains { Set([$0.first, $0.second]) == [.noteBold, .search] })
        #expect(clashes.contains { Set([$0.first, $0.second]) == [.texBuild, .search] })
    }

    @Test func backByArrowYieldsToTextButNotToOtherAppKeys() {
        let back = ShortcutTable.shortcut(.back)
        #expect(back.bindings.map(\.combo) == [KeyCombo("["), KeyCombo(.leftArrow)])
        var table = ShortcutTable.standard
        table.append(Shortcut(.search, .app, keys: [.init(KeyCombo(.leftArrow))]))
        #expect(ShortcutTable.clashes(in: table).map(\.first) == [.back, .lineStart])
    }

    @Test func tabNumbersRunOneToNineWithNineTheLast() {
        #expect((1...9).compactMap(ShortcutID.tab(number:)).map { $0.tabNumber } == (1...9).map { $0 })
        #expect(ShortcutID.tab(number: 9) == .lastTab && ShortcutID.tab(number: 0) == nil && ShortcutID.tab(number: 10) == nil)
        #expect(ShortcutTable.shortcut(.lastTab).key == KeyCombo("9"))
    }

    static let combo = Gen.int(in: 0...15).map { mask in KeyCombo.Modifiers(rawValue: mask) }
    static let scope = Gen.int(in: 0...(Shortcut.Scope.allCases.count - 1)).map { Shortcut.Scope.allCases[$0] }
    static let id = Gen.int(in: 0...(ShortcutID.allCases.count - 1)).map { ShortcutID.allCases[$0] }
    static let key = Gen.int(in: 0...12).map { n -> KeyCombo.Key in
        let keys: [KeyCombo.Key] = [.leftArrow, .rightArrow, .tab, .return, .space]
        return n < keys.count ? keys[n] : .character(Array("bei[]tkw9")[n - keys.count])
    }

    // 어느 명령을 표에 더해도, 더한 명령과 겹친다고 보고되는 짝은 실제로 같은 키를 함께 듣는 자리의 명령이다.
    @Test func everyReportedClashSharesAKeyInOverlappingScopes() async {
        await propertyCheck(input: Self.id, Self.scope, Self.key, Self.combo) { id, scope, key, modifiers in
            var table = ShortcutTable.standard
            table.append(Shortcut(id, .app, scope, keys: [.init(KeyCombo(key, modifiers))]))
            for clash in ShortcutTable.clashes(in: table) {
                guard let first = table.first(where: { $0.id == clash.first }), let second = table.last(where: { $0.id == clash.second })
                else { return #expect(Bool(false)) }
                #expect(first.scope.overlaps(second.scope))
                #expect(first.bindings.contains { $0.combo == clash.combo } && second.bindings.contains { $0.combo == clash.combo })
            }
            let added = KeyCombo(key, modifiers)
            let taken = ShortcutTable.standard.contains { s in
                s.scope.overlaps(scope) && s.bindings.contains { $0.combo == added && !($0.yieldsToText && scope.isText) }
            }
            #expect(taken == !ShortcutTable.clashes(in: table).isEmpty)
        }
    }

    @Test func clicksOpenLikeSafari() {
        #expect(LinkClick([]) == .here)
        #expect(LinkClick(.command) == .tabBehind)
        #expect(LinkClick([.command, .shift]) == .tab)
        #expect(LinkClick([.command, .option]) == .beside)
        #expect(LinkClick([.command, .control]) == .tabBehind)
        #expect(LinkClick(.shift) == .here && LinkClick(.option) == .here)
    }
}
