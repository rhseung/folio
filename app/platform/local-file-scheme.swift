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

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url, let root else { return task.didFailWithError(URLError(.fileDoesNotExist)) }
        let file = URL(fileURLWithPath: url.path(percentEncoded: false)).standardizedFileURL
        guard file.path.hasPrefix(root.path + "/"), let data = LocalFile.read(file) else {
            return task.didFailWithError(URLError(.fileDoesNotExist))
        }
        let type = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        task.didReceive(URLResponse(url: url, mimeType: type, expectedContentLength: data.count, textEncodingName: nil))
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}
}
