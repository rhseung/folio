import Foundation
import Observation
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct LiveTime<Content: View>: View {
    let workspace: Workspace
    @ViewBuilder let content: (Date) -> Content

    init(_ workspace: Workspace, @ViewBuilder content: @escaping (Date) -> Content) {
        self.workspace = workspace
        self.content = content
    }

    var body: some View { content(workspace.liveNow) }
}
