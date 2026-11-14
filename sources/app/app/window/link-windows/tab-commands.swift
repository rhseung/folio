import FolioDomain
import SwiftUI

#if os(macOS)
import AppKit
import WebKit

struct TabCommands: Commands {
    @FocusedValue(\.windowTabs) private var tabs

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button(.tabsNew) { tabs?.open() }
                .keyboardShortcut("t")
                .disabled(tabs == nil)
        }
        // 시스템의 닫기(⌘W)를 바꾼다. 그대로 두면 탭 명령이 키를 받기 전에 창 전체가 닫힌다.
        CommandGroup(replacing: .saveItem) {
            Button(.tabsClose) {
                guard NSApp.keyWindow?.sheetParent == nil else { return }
                if let tabs { tabs.closeSelected() } else { NSApp.keyWindow?.performClose(nil) }
            }
            .keyboardShortcut("w")
            Button(.tabsCloseWindow) { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w", modifiers: [.command, .shift])
        }
    }
}
#endif
