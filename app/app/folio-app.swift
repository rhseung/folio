import SwiftUI

@main
struct FolioApp: App {
    @State private var workspace = Workspace()
    /// Under tests the app is only their host: no window of its own and no focus taken from what the user is doing.
    private static let hostingTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    init() {
        #if os(macOS)
        if Self.hostingTests { NSApplication.shared.setActivationPolicy(.prohibited) }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                #if os(macOS)
                // Three columns side by side are the app's layout; narrower, pages stacked their figures into slivers.
                .frame(minWidth: 1120, minHeight: 640)
                #endif
                .appServices()
                .followsAppearance()
                .environment(workspace)
                .buttonStyle(.pointing(.automatic))
        }
        .defaultSize(width: 1520, height: 860)
        .defaultLaunchBehavior(Self.hostingTests ? .suppressed : .automatic)
        #if os(macOS)
        // The compact row keeps the frame around the content panel thin.
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        #endif
        .commands { SettingsCommands() }
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
