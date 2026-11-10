import SwiftUI

@main
struct FolioApp: App {
    @State private var workspace = Workspace()
    @State private var paneMemory = Self.hostingTests ? nil : PaneMemoryStore(defaults: .standard)
    /// Under tests the app is only their host: no window of its own and no focus taken from what the user is doing.
    private static let hostingTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    static let mainWindow = "main"

    init() {
        #if os(macOS)
        if Self.hostingTests { NSApplication.shared.setActivationPolicy(.prohibited) }
        // The window draws its tabs in its toolbar row (`TabBar`); AppKit's tab bar would add a row of its own and a
        // second kind of tab, and its menu items with it.
        NSWindow.allowsAutomaticWindowTabbing = false
        #endif
    }

    var body: some Scene {
        // The id names the saved window frame. Without it the name is the content's type, which holds the addresses of
        // private types and so changes with every build: each new build forgot the window and opened it afresh.
        // A window opened by a link carries the link; the first window, and one opened from the menu, carries none.
        WindowGroup(id: Self.mainWindow, for: WindowRequest.self) { $request in
            RootView(request: request)
                #if os(macOS)
                // Bounded both ways, so the window's least size is this frame's own: with only a least size the
                // hosting view measured the whole window's content for it on every layout of a resize or a drag (#62).
                .frame(minWidth: Theme.Size.windowMin.width, maxWidth: .infinity, minHeight: Theme.Size.windowMin.height, maxHeight: .infinity)
                #endif
                .appServices()
                .followsAppearance()
                .environment(workspace)
                .environment(\.paneMemory, paneMemory)
                .buttonStyle(.pointing(.automatic))
        }
        .defaultSize(Theme.Size.windowIdeal)
        #if os(macOS)
        // Only a window with nothing saved. A saved frame bigger than its screen AppKit already cuts to the screen.
        .defaultWindowPlacement { _, context in
            WindowPlacement(.center, size: WindowSize.opening(in: context.defaultDisplay.visibleRect.size))
        }
        .defaultLaunchBehavior(Self.hostingTests ? .suppressed : .automatic)
        // No title bar or toolbar: the window draws its own 48pt top row (`TitleRow`), a height no toolbar has (#62).
        .windowStyle(.hiddenTitleBar)
        #endif
        .commands {
            SettingsCommands()
            NavigationCommands()
            ColumnCommands()
            OutlineCommands()
            PaneCommands()
            WhatsNewCommands()
            InputGuideCommands()
            #if os(macOS)
            TabCommands()
            MathCommands()
            #endif
        }
    }
}

/// ⌘, opens the settings page in the main window; settings are a page there, not a window of their own.
private struct SettingsCommands: Commands {
    @FocusedValue(\.showSettings) private var showSettings

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button(.appSettingsMenu) { showSettings?(nil) }
                .keyboardShortcut(",")
                .disabled(showSettings == nil)
        }
    }
}

/// 도움말 › 새 기능 (#415): the page of what each release changed, in the window in front. No key: it is opened rarely.
private struct WhatsNewCommands: Commands {
    @FocusedValue(\.openPlace) private var openPlace

    var body: some Commands {
        CommandGroup(after: .help) {
            Button(.whatsNewTitle) { openPlace?(.place(.whatsNew)) }
                .disabled(openPlace == nil)
        }
    }
}

/// 도움말 › 입력 안내 (⌘/, #395): sent down the responder chain to the note being written, which opens the guide for
/// its math syntax; with none, the window opens it for the syntax new notes get. ⌘/ is taken by nothing else in the
/// app or the system (⇧⌘/ is the system's help search).
private struct InputGuideCommands: Commands {
    @FocusedValue(\.showInputGuide) private var show

    var body: some Commands {
        CommandGroup(after: .help) {
            Button(.notesGuideTitle) {
                #if os(macOS)
                let sent = NSApp.sendAction(#selector(SourceTextView.showInputGuide(_:)), to: nil, from: nil)
                #else
                let sent = UIApplication.shared.sendAction(#selector(SourceTextView.showInputGuide(_:)), to: nil, from: nil, for: nil)
                #endif
                if !sent { show?(nil) }
            }
            .keyboardShortcut("/")
        }
    }
}

/// 보기 › 목차 보기·숨기기 for the note in the focused pane, as the note's bar button does (#387). No key yet: keys
/// come with the table of them (#116).
private struct OutlineCommands: Commands {
    @FocusedValue(\.outlineCommand) private var outline

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button(outline?.shown == true ? String(localized: .notesOutlineHide) : String(localized: .notesOutlineShow)) { outline?.toggle() }
                .disabled(outline == nil)
        }
    }
}

/// 보기 › 칸 폭 맞추기, as a divider's double click (Mac) or long press (iPad) does, and 칸 접기 for the focused pane,
/// as its menu does (2026-11-08 사용자). No keys yet: keys come with the table of them (#116).
private struct PaneCommands: Commands {
    @FocusedValue(\.frontPanes) private var panes

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button(.panesEven) { panes?.even() }
                .disabled((panes?.count ?? 0) < 2)
            Button(.panesCollapse) { if let panes { panes.collapse(panes.focus) } }
                .disabled(!(panes.map { $0.canCollapse($0.focus) } ?? false))
        }
    }
}

#if os(macOS)
/// 편집 › 수식 기호 목록: the menu typing `\` in a formula opens, with every symbol of the note's syntax, sent down the
/// responder chain to the note being written, which beeps when its caret is in no formula (#392). No key: ⌃Space is
/// the input source switch (2026-11-09 사용자), and `\` itself is the key. Not on the iPad, which has no completion
/// menu yet (#31); its path to every symbol is the palette under the note bar's f(x).
private struct MathCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Button(.notesMathSymbolsMenu) {
                if !NSApp.sendAction(#selector(SourceTextView.showMathSymbols(_:)), to: nil, from: nil) { NSSound.beep() }
            }
        }
    }
}
#endif

/// 보기 › 구역 열 보기·숨기기 (⌥⌘S) for the focused pane's list column, beside the sidebar's ⌃⌘S: hides a docked
/// column by hand, and shows a folded one again, docked where it fits and over the page where it doesn't (#62).
private struct ColumnCommands: Commands {
    @FocusedValue(\.columnCommand) private var column

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button(column.map { ColumnSplit<EmptyView, EmptyView>.label($0.kind, shown: $0.shown) } ?? String(localized: .designColumnShowSections)) {
                column?.toggle()
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
            .disabled(column == nil)
        }
    }
}
