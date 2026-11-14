#if DEBUG && os(macOS)
import AppKit
import FolioDomain
import Observation
import SwiftUI
import WebKit

extension View {
    @ViewBuilder func snapshotKey() -> some View {
        if ProcessInfo.processInfo.environment["FOLIO_SNAPSHOT_KEY"] != nil {
            environment(\.controlActiveState, .key)
        } else {
            self
        }
    }
}
#endif
