#if os(macOS) && (DEBUG || RESIZE_PROBE)
import AppKit
import FolioDomain
import QuartzCore
import SwiftUI

struct ResizeMarker: NSViewRepresentable {
    let name: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let table = ResizeProbe.marked[name] ?? NSHashTable<NSView>.weakObjects()
        table.add(view)
        ResizeProbe.marked[name] = table
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}
#endif
