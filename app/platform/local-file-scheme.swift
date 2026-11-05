import FolioStorage
import UniformTypeIdentifiers
import WebKit

/// Serves a note's images to its web view. A page loaded from a string can't read `file:` URLs (the web process has
/// no access to the iCloud folder), so relative links resolve against this scheme and the app reads the files.
@MainActor final class LocalFileScheme: NSObject, WKURLSchemeHandler {
    static let scheme = "folio-file"
    /// Only files under this folder are served, so a note can't pull in arbitrary files by `../`.
    var root: URL?

    /// The page base for a folder: `assets/a.png` written in a note there resolves to a URL this handler serves.
    static func base(for folder: URL?) -> URL? {
        guard let folder else { return nil }
        var c = URLComponents()
        c.scheme = scheme
        c.host = "local"
        c.path = folder.standardizedFileURL.path + "/"
        return c.url
    }

    /// The note folder's parent, so notes in a subfolder still reach `Notes/assets` by `../assets`.
    static func root(for folder: URL?) -> URL? { folder?.standardizedFileURL.deletingLastPathComponent() }

    private var running = Set<ObjectIdentifier>()

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url, let root else { return task.didFailWithError(URLError(.fileDoesNotExist)) }
        let file = URL(fileURLWithPath: url.path(percentEncoded: false)).standardizedFileURL
        guard file.path.hasPrefix(root.path + "/") else { return task.didFailWithError(URLError(.fileDoesNotExist)) }
        let id = ObjectIdentifier(task as AnyObject)
        running.insert(id)
        Task {
            let data = await Self.read(file)
            // A task the page stopped (the note changed, the view closed) may not be answered.
            guard running.remove(id) != nil else { return }
            guard let data else { return task.didFailWithError(URLError(.fileDoesNotExist)) }
            let type = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            task.didReceive(URLResponse(url: url, mimeType: type, expectedContentLength: data.count, textEncodingName: nil))
            task.didReceive(data)
            task.didFinish()
        }
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) { running.remove(ObjectIdentifier(task as AnyObject)) }

    /// Off the main thread: a coordinated read of a file iCloud hasn't downloaded waits for the download.
    nonisolated static func read(_ file: URL) async -> Data? { LocalFile.read(file) }
}
