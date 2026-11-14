import FolioDomain
import SwiftUI

struct NavigationCommands: Commands {
    @FocusedValue(\.navigator) private var navigator
    #if os(macOS)
    @FocusedValue(\.windowTabs) private var tabs
    #endif

    var body: some Commands {
        CommandMenu(Text(.navigationMenu)) {
            Button(.navigationBack) { navigator?.back() }
                .keyboardShortcut("[")
                .disabled(navigator?.history.canGoBack != true)
            Button(.navigationForward) { navigator?.forward() }
                .keyboardShortcut("]")
                .disabled(navigator?.history.canGoForward != true)
            #if os(macOS)
            Divider()
            Button(.tabsNext) { tabs?.selectNext() }
                .keyboardShortcut(.tab, modifiers: .control)
                .disabled((tabs?.count ?? 0) < 2)
            Button(.tabsPrevious) { tabs?.selectPrevious() }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
                .disabled((tabs?.count ?? 0) < 2)
            Menu(String(localized: .tabsPick)) {
                ForEach(1...8, id: \.self) { n in
                    Button(.tabsNumber(n)) { tabs?.select(number: n) }
                        .keyboardShortcut(KeyEquivalent(Character(String(n))))
                        .disabled((tabs?.count ?? 0) < n)
                }
                Button(.tabsLast) { tabs?.select(number: 9) }
                    .keyboardShortcut("9")
                    .disabled((tabs?.count ?? 0) < 2)
            }
            #endif
        }
    }
}
