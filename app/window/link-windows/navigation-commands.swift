import FolioDomain
import SwiftUI

struct NavigationCommands: Commands {
    @FocusedValue(\.navigator) private var navigator
    #if os(macOS)
    @FocusedValue(\.windowTabs) private var tabs
    #endif

    var body: some Commands {
        CommandMenu(Text(.navigationMenu)) {
            CommandButton(.back) { navigator?.back() }
                .disabled(navigator?.history.canGoBack != true)
            CommandButton(.forward) { navigator?.forward() }
                .disabled(navigator?.history.canGoForward != true)
            #if os(iOS)
            // iPad의 메뉴 키는 글 칸의 키보다 늦게 받으므로 글 칸에서는 ⌘←·⌘→가 줄 처음·끝으로 간다. Mac은 메뉴 키를 먼저
            // 받아 `TextYieldingShortcuts`가 따로 받는다.
            ForEach(ShortcutTable.shortcut(.back).bindings.filter(\.yieldsToText), id: \.self) { binding in
                CommandButton(.back, key: binding.combo) { navigator?.back() }
                    .disabled(navigator?.history.canGoBack != true)
            }
            ForEach(ShortcutTable.shortcut(.forward).bindings.filter(\.yieldsToText), id: \.self) { binding in
                CommandButton(.forward, key: binding.combo) { navigator?.forward() }
                    .disabled(navigator?.history.canGoForward != true)
            }
            #endif
            #if os(macOS)
            Divider()
            CommandButton(.nextTab) { tabs?.selectNext() }
                .disabled((tabs?.count ?? 0) < 2)
            CommandButton(.previousTab) { tabs?.selectPrevious() }
                .disabled((tabs?.count ?? 0) < 2)
            Menu(String(localized: .tabsPick)) {
                ForEach(1...9, id: \.self) { n in
                    if let id = ShortcutID.tab(number: n) {
                        CommandButton(id) { tabs?.select(number: n) }
                            .disabled((tabs?.count ?? 0) < (n == 9 ? 2 : n))
                    }
                }
            }
            #endif
        }
    }
}
