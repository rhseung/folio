import SwiftUI

/// "편집기로 열기": a code folder (a project in `Assignments`) opened as a project in an editor installed on this Mac
/// (#120). Only editors that are installed are listed, and none at all leaves the menu out. iPadOS has no editor to hand
/// a folder to, so there the menu is empty.
struct EditorMenu: View {
    let url: URL

    var body: some View {
        #if os(macOS)
        let editors = Self.installed
        if !editors.isEmpty {
            Menu(String(localized: .fileViewOpenInEditor)) {
                ForEach(editors, id: \.app) { editor in
                    Button(editor.name) {
                        NSWorkspace.shared.open([url], withApplicationAt: editor.app, configuration: NSWorkspace.OpenConfiguration())
                    }
                }
            }
        }
        #endif
    }

    #if os(macOS)
    /// By bundle ID rather than by asking which apps open folders: Finder and archivers say they do too.
    static let editors = [
        "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "dev.zed.Zed", "com.apple.dt.Xcode", "com.sublimetext.4",
        "com.jetbrains.intellij", "com.jetbrains.pycharm", "com.jetbrains.CLion",
    ]

    static var installed: [(name: String, app: URL)] {
        editors.compactMap { id in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map { app in
                (FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: ""), app)
            }
        }
    }
    #endif
}
