import SwiftUI

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
    // 폴더를 여는 앱을 묻지 않고 bundle ID로 찾는다. Finder와 압축 프로그램도 폴더를 연다고 답하기 때문이다.
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
