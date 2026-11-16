import SwiftUI

@main
struct FolioApp: App {
    @State private var workspace = Workspace()
    @State private var paneMemory = Self.hostingTests ? nil : PaneMemoryStore.forThisRun()
    private static let hostingTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    static let mainWindow = "main"

    init() {
        #if os(macOS)
        if Self.hostingTests { NSApplication.shared.setActivationPolicy(.prohibited) }
        // 창은 툴바 줄에 탭을 직접 그린다(`TabBar`). AppKit의 탭 막대를 켜면 줄이 하나 더 생기고, 다른 종류의 탭과 그 메뉴
        // 항목도 함께 생긴다.
        NSWindow.allowsAutomaticWindowTabbing = false
        #endif
    }

    var body: some Scene {
        // id가 저장된 창 frame의 이름이 된다. id가 없으면 내용의 타입 이름을 쓰는데, 이 이름에는 private 타입의 주소가
        // 들어 있어 빌드할 때마다 바뀐다. 그래서 새로 빌드할 때마다 창의 위치와 크기를 잊고 처음 크기로 열었다.
        WindowGroup(id: Self.mainWindow, for: WindowRequest.self) { $request in
            RootView(request: request)
                #if os(macOS)
            .mainWindowFrame(firstRun: workspace.isInFirstRun)
                #endif
                .appServices()
                .followsAppearance()
                .environment(workspace)
                .environment(\.paneMemory, paneMemory)
                .buttonStyle(.pointing(.automatic))
        }
        .defaultSize(Theme.Size.windowIdeal)
        #if os(macOS)
        .defaultWindowPlacement { _, context in
            WindowPlacement(.center, size: WindowSize.opening(in: context.defaultDisplay.visibleRect.size))
        }
        .defaultLaunchBehavior(Self.hostingTests ? .suppressed : .automatic)
        .windowResizability(.contentSize)
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

private struct WhatsNewCommands: Commands {
    @FocusedValue(\.openPlace) private var openPlace

    var body: some Commands {
        CommandGroup(after: .help) {
            Button(.whatsNewTitle) { openPlace?(.place(.whatsNew)) }
                .disabled(openPlace == nil)
        }
    }
}

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

private struct OutlineCommands: Commands {
    @FocusedValue(\.outlineCommand) private var outline

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button(outline?.shown == true ? String(localized: .notesOutlineHide) : String(localized: .notesOutlineShow)) {
                outline?.toggle()
            }
            .disabled(outline == nil)
        }
    }
}

private struct PaneCommands: Commands {
    @FocusedValue(\.frontPanes) private var panes
    @FocusedValue(\.layoutChoices) private var layouts

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            if let layouts { LayoutMenu(choices: layouts) }
            Button(.panesEven) { panes?.even() }
                .disabled((panes?.count ?? 0) < 2)
            Button(.panesCollapse) { if let panes { panes.collapse(panes.focus) } }
                .disabled(!(panes.map { $0.canCollapse($0.focus) } ?? false))
        }
    }
}

#if os(macOS)
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

private struct ColumnCommands: Commands {
    @FocusedValue(\.columnCommand) private var column

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button(
                column.map { ColumnSplit<EmptyView, EmptyView>.label($0.kind, shown: $0.shown) }
                    ?? String(localized: .designColumnShowSections)
            ) {
                column?.toggle()
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
            .disabled(column == nil)
        }
    }
}
