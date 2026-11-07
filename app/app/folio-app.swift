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
                .frame(minWidth: Theme.Size.windowMin.width, minHeight: Theme.Size.windowMin.height)
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
        // The compact row keeps the frame around the content panel thin.
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        #endif
        .commands {
            SettingsCommands()
            NavigationCommands()
            #if os(macOS)
            TabCommands()
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
