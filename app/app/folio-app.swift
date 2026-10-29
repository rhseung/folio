import SwiftUI

@main
struct FolioApp: App {
    @State private var workspace = Workspace()

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
            Button("설정…") { showSettings?(nil) }
                .keyboardShortcut(",")
                .disabled(showSettings == nil)
        }
    }
}
