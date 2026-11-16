import Foundation

// 단축키의 단일 출처다. 메뉴 막대 명령과 화면의 키가 모두 이 표에서 키를 읽는다. 관례 키(굵게, 줄 처음, 확대)도
// 고정 항목으로 두어 어느 키가 예약돼 있는지 한 곳에서 보이게 한다.
public enum ShortcutTable {
    public static let standard: [Shortcut] = [
        Shortcut(.back, .navigation, keys: [.init(KeyCombo("[")), .init(KeyCombo(.leftArrow), yieldsToText: true)]),
        Shortcut(.forward, .navigation, keys: [.init(KeyCombo("]")), .init(KeyCombo(.rightArrow), yieldsToText: true)]),

        Shortcut(.newTab, .tabs, keys: [.init(KeyCombo("t"))]),
        Shortcut(.nextTab, .tabs, keys: [.init(KeyCombo(.tab, .control))]),
        Shortcut(.previousTab, .tabs, keys: [.init(KeyCombo(.tab, [.control, .shift]))]),
        Shortcut(.tab1, .tabs, keys: [.init(KeyCombo("1"))]),
        Shortcut(.tab2, .tabs, keys: [.init(KeyCombo("2"))]),
        Shortcut(.tab3, .tabs, keys: [.init(KeyCombo("3"))]),
        Shortcut(.tab4, .tabs, keys: [.init(KeyCombo("4"))]),
        Shortcut(.tab5, .tabs, keys: [.init(KeyCombo("5"))]),
        Shortcut(.tab6, .tabs, keys: [.init(KeyCombo("6"))]),
        Shortcut(.tab7, .tabs, keys: [.init(KeyCombo("7"))]),
        Shortcut(.tab8, .tabs, keys: [.init(KeyCombo("8"))]),
        Shortcut(.lastTab, .tabs, keys: [.init(KeyCombo("9"))]),

        Shortcut(.closeTab, .window, .app, .fixed, keys: [.init(KeyCombo("w"))]),
        Shortcut(.closeWindow, .window, .app, .fixed, keys: [.init(KeyCombo("w", [.command, .shift]))]),
        Shortcut(.toggleSidebar, .window, keys: [.init(KeyCombo("s", [.command, .control]))]),
        Shortcut(.toggleColumn, .window, keys: [.init(KeyCombo("s", [.command, .option]))]),

        Shortcut(.search, .app, keys: [.init(KeyCombo("k"))]),
        Shortcut(.settings, .app, .app, .fixed, keys: [.init(KeyCombo(","))]),
        Shortcut(.inputGuide, .app, keys: [.init(KeyCombo("/"))]),

        Shortcut(.noteViewToggle, .notes, .note, keys: [.init(KeyCombo("e"))]),
        Shortcut(.noteBold, .notes, .noteEditing, .fixed, keys: [.init(KeyCombo("b"))]),
        Shortcut(.noteItalic, .notes, .noteEditing, .fixed, keys: [.init(KeyCombo("i"))]),
        Shortcut(.texBuild, .notes, .texEditing, keys: [.init(KeyCombo("b"))]),
        Shortcut(.lineStart, .notes, .text, .fixed, keys: [.init(KeyCombo(.leftArrow))]),
        Shortcut(.lineEnd, .notes, .text, .fixed, keys: [.init(KeyCombo(.rightArrow))]),

        Shortcut(.zoomIn, .materials, .materialView, .fixed, keys: [.init(KeyCombo("="))]),
        Shortcut(.zoomOut, .materials, .materialView, .fixed, keys: [.init(KeyCombo("-"))]),
        Shortcut(.zoomFit, .materials, .materialView, .fixed, keys: [.init(KeyCombo("0"))]),
    ]

    public static func shortcut(_ id: ShortcutID, in table: [Shortcut] = standard) -> Shortcut {
        table.first { $0.id == id } ?? Shortcut(id, .app, keys: [])
    }

    public struct Clash: Hashable, Sendable {
        public var first: ShortcutID
        public var second: ShortcutID
        public var combo: KeyCombo
    }

    // 함께 듣는 자리에서 같은 키를 가진 두 명령이다. 글 칸에 양보하는 키는 글 칸 자리의 키와 겹치지 않는다.
    public static func clashes(in table: [Shortcut]) -> [Clash] {
        var found: [Clash] = []
        for (i, a) in table.enumerated() {
            for b in table[(i + 1)...] where a.scope.overlaps(b.scope) {
                for x in a.bindings {
                    for y in b.bindings where x.combo == y.combo {
                        if (x.yieldsToText && b.scope.isText) || (y.yieldsToText && a.scope.isText) { continue }
                        found.append(Clash(first: a.id, second: b.id, combo: x.combo))
                    }
                }
            }
        }
        return found
    }
}
