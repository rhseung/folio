import FolioDomain
import SwiftUI
import WebKit

/// The live-preview note editor (web/src/editor.js) in a web view. Unlike the reader, this page runs script: it is
/// the bundled editor, and the note's text only ever enters it as editor content, never as markup.
struct MarkdownEditor {
    @Binding var text: String
    var baseURL: URL?
    var math: MathSyntax
    /// Live preview; off shows the raw markdown.
    var live: Bool
    /// Set to insert at the cursor; cleared once inserted.
    @Binding var insert: String?
    /// Saves a dropped or pasted file and returns the markdown that links it, or nil when it couldn't be saved.
    var saveFile: (String, Data) -> String?
    var openNote: (String) -> Void

    func page(accent: CourseAccent) -> String {
        "<!doctype html><html><head><meta charset=utf-8><style>\(NoteStyle.variables(accent: accent))\(NoteStyle.css)</style></head>"
            + "<body class=\"note editor\"><div id=\"editor\"></div></body></html>"
    }

    @MainActor func makeWebView(_ coordinator: Coordinator, accent: CourseAccent) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.addUserScript(WKUserScript(source: NoteStyle.editor, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        config.userContentController.add(coordinator, name: "folio")
        coordinator.files.root = LocalFileScheme.root(for: baseURL)
        config.setURLSchemeHandler(coordinator.files, forURLScheme: LocalFileScheme.scheme)
        #if os(macOS)
        let view = EditorWebView(frame: .zero, configuration: config)
        view.receiveFile = { [weak coordinator] name, data, point in
            guard let coordinator, let link = coordinator.parent.saveFile(name, data) else { return }
            coordinator.call("cb.insertAtPoint", point.x, point.y, link)
        }
        #else
        let view = WKWebView(frame: .zero, configuration: config)
        #endif
        view.navigationDelegate = coordinator
        #if os(macOS)
        view.setValue(false, forKey: "drawsBackground")
        #else
        view.isOpaque = false
        view.backgroundColor = .clear
        #endif
        coordinator.view = view
        view.loadHTMLString(page(accent: accent), baseURL: LocalFileScheme.base(for: baseURL))
        return view
    }

    @MainActor func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor func update(_ coordinator: Coordinator) {
        let previous = coordinator.parent
        coordinator.parent = self
        guard coordinator.ready else { return }
        if text != coordinator.known { coordinator.load() }
        if math != previous.math { coordinator.call("cb.setSyntax", math.rawValue) }
        if live != previous.live { coordinator.call("cb.setLive", live) }
        if let insert {
            coordinator.call("cb.insert", insert)
            DispatchQueue.main.async { self.insert = nil }
        }
    }

    @MainActor final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: MarkdownEditor
        weak var view: WKWebView?
        let files = LocalFileScheme()
        var ready = false
        /// The text as the editor last reported it, so its own edits coming back through the binding don't reload it.
        var known: String?

        init(_ parent: MarkdownEditor) { self.parent = parent }

        func load() {
            known = parent.text
            call("cb.load", ["text": parent.text, "syntax": parent.math.rawValue, "live": parent.live] as [String: Any])
        }

        /// Calls `function` with JSON arguments; JSON keeps note text from being read as script.
        func call(_ function: String, _ arguments: Any...) {
            guard let data = try? JSONSerialization.data(withJSONObject: arguments, options: [.fragmentsAllowed]),
                  let json = String(data: data, encoding: .utf8) else { return }
            view?.evaluateJavaScript("\(function)(...\(json))")
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "ready":
                ready = true
                load()
            case "change":
                guard let text = body["text"] as? String else { return }
                known = text
                parent.text = text
            case "file":
                guard let name = body["name"] as? String, let base64 = body["data"] as? String, let data = Data(base64Encoded: base64),
                      let link = parent.saveFile((name as NSString).lastPathComponent, data) else { return }
                call("cb.insertAt", body["pos"] as? Int ?? 0, link)
            case "open":
                if let wiki = body["wiki"] as? String {
                    parent.openNote(String(wiki.split(separator: "#").first ?? ""))
                } else if let href = body["href"] as? String {
                    open(href)
                }
            default:
                break
            }
        }

        func open(_ href: String) {
            guard let url = URL(string: href, relativeTo: parent.baseURL) else { return }
            switch url.scheme {
            case "http", "https":
                #if os(macOS)
                NSWorkspace.shared.open(url)
                #else
                UIApplication.shared.open(url)
                #endif
            case "file" where url.pathExtension == "md":
                parent.openNote(url.deletingPathExtension().lastPathComponent)
            default:
                break
            }
        }

        private var pageLoaded = false

        /// Only the editor page itself loads; links are handled above, never followed inside the web view.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            if pageLoaded { return .cancel }
            pageLoaded = true
            return .allow
        }
    }
}

#if os(macOS)
/// Takes the drags WebKit can't hand the page as files: file promises (screenshot tools like CleanShot, Photos,
/// browser images) and bare image data. Left to WebKit, they dropped a broken image into the editor's markup.
final class EditorWebView: WKWebView {
    var receiveFile: ((String, Data, CGPoint) -> Void)?
    private static let promiseQueue = OperationQueue()

    // The app's Edit menu takes ⌘Z for the window's undo manager before the page sees the key, and WebKit's own undo
    // knows nothing of CodeMirror's history, so both the keys and the menu actions go to the editor here.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard (window?.firstResponder as? NSView)?.isDescendant(of: self) == true,
              flags.subtracting(.shift) == .command, event.charactersIgnoringModifiers?.lowercased() == "z" else {
            return super.performKeyEquivalent(with: event)
        }
        evaluateJavaScript(flags.contains(.shift) ? "cb.redo()" : "cb.undo()")
        return true
    }

    @objc func undo(_ sender: Any?) { evaluateJavaScript("cb.undo()") }
    @objc func redo(_ sender: Any?) { evaluateJavaScript("cb.redo()") }

    private func handlesNatively(_ info: NSDraggingInfo) -> Bool {
        let board = info.draggingPasteboard
        if board.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) { return false }
        return board.canReadObject(forClasses: [NSFilePromiseReceiver.self], options: nil)
            || board.canReadObject(forClasses: [NSImage.self], options: nil)
    }

    override func draggingEntered(_ info: NSDraggingInfo) -> NSDragOperation {
        let operation = super.draggingEntered(info)
        return handlesNatively(info) ? .copy : operation
    }

    override func draggingUpdated(_ info: NSDraggingInfo) -> NSDragOperation {
        let operation = super.draggingUpdated(info)
        return handlesNatively(info) ? .copy : operation
    }

    override func performDragOperation(_ info: NSDraggingInfo) -> Bool {
        guard handlesNatively(info) else { return super.performDragOperation(info) }
        // The page's client coordinates, which posAtCoords takes; the web view is flipped like the page.
        let local = convert(info.draggingLocation, from: nil)
        let point = CGPoint(x: local.x, y: isFlipped ? local.y : bounds.height - local.y)
        let board = info.draggingPasteboard
        if let promises = board.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver], !promises.isEmpty {
            let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            // folio:not-an-action a temporary folder for pasted files
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for promise in promises {
                promise.receivePromisedFiles(atDestination: folder, options: [:], operationQueue: Self.promiseQueue) { [weak self] url, error in
                    guard error == nil, let data = try? Data(contentsOf: url) else { return }
                    let name = url.lastPathComponent
                    // folio:not-an-action a temporary folder for pasted files
                    try? FileManager.default.removeItem(at: url)
                    Task { @MainActor in self?.receiveFile?(name, data, point) }
                }
            }
            return true
        }
        guard let image = (board.readObjects(forClasses: [NSImage.self]) as? [NSImage])?.first, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return false }
        receiveFile?("Dropped \(Date.now.formatted(.iso8601.dateSeparator(.dash).timeSeparator(.omitted))).png", png, point)
        return true
    }
}

extension MarkdownEditor: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeWebView(context.coordinator, accent: context.environment.accent) }
    func updateNSView(_ view: WKWebView, context: Context) { update(context.coordinator) }
    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "folio")
    }
}
#else
extension MarkdownEditor: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeWebView(context.coordinator, accent: context.environment.accent) }
    func updateUIView(_ view: WKWebView, context: Context) { update(context.coordinator) }
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "folio")
    }
}
#endif
