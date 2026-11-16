import FolioDomain
import FolioStorage
import WebKit

@MainActor final class WidgetFiles: NSObject, WKURLSchemeHandler {
    static let scheme = "folio-widget"

    var folder: URL?

    static func allows(_ url: URL) -> Bool {
        url.scheme == "about" || (url.scheme == scheme && url.host == "widget")
    }

    private var running = Set<ObjectIdentifier>()

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url, url.host == "widget", let id = UUID(uuidString: url.lastPathComponent) else {
            return task.didFailWithError(URLError(.fileDoesNotExist))
        }
        let file = folder.flatMap { StandardLayout.widgetFile(id, noteFolder: $0) }
        let key = ObjectIdentifier(task as AnyObject)
        running.insert(key)
        Task {
            let read = if let file { await LocalFileScheme.read(file) } else { Data?.none }
            guard running.remove(key) != nil else { return }
            let data = NoteWidget.withPolicy(read ?? Self.notice(file))
            let headers = ["Content-Type": "text/html; charset=utf-8", "Content-Security-Policy": NoteWidget.policy]
            task.didReceive(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!)
            task.didReceive(data)
            task.didFinish()
        }
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) { running.remove(ObjectIdentifier(task as AnyObject)) }

    static func notice(_ file: URL?) -> Data {
        let text =
            switch file {
            case nil: String(localized: .notesWidgetNoCourse)
            case let file? where LocalFile.exists(file): String(localized: .notesWidgetUnreadable(file.lastPathComponent))
            case let file?: String(localized: .notesWidgetMissing(file.lastPathComponent))
            }
        let escaped =
            text
            .replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        return Data("<!doctype html><p style=\"color:var(--text-3);font-size:12px;padding:12px\">\(escaped)</p>".utf8)
    }
}
