import FolioStorage
import UniformTypeIdentifiers
import WebKit

// 문자열로 불러온 페이지는 `file:` URL을 읽지 못한다(웹 프로세스는 iCloud 폴더에 접근하지 못한다). 그래서 상대 링크를 이 scheme으로 풀고 앱이 파일을 읽는다.
@MainActor final class LocalFileScheme: NSObject, WKURLSchemeHandler {
    static let scheme = "folio-file"
    // 노트가 `../`로 아무 파일이나 가져오지 못하도록 이 폴더 아래의 파일만 내준다.
    var root: URL?

    static func base(for folder: URL?) -> URL? {
        guard let folder else { return nil }
        var c = URLComponents()
        c.scheme = scheme
        c.host = "local"
        c.path = folder.standardizedFileURL.path + "/"
        return c.url
    }

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
            guard running.remove(id) != nil else { return }
            guard let data else { return task.didFailWithError(URLError(.fileDoesNotExist)) }
            let type = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            task.didReceive(URLResponse(url: url, mimeType: type, expectedContentLength: data.count, textEncodingName: nil))
            task.didReceive(data)
            task.didFinish()
        }
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) { running.remove(ObjectIdentifier(task as AnyObject)) }

    // main thread 밖에서 읽는다. iCloud가 아직 내려받지 않은 파일을 조율해서 읽으면 다운로드가 끝날 때까지 기다린다.
    nonisolated static func read(_ file: URL) async -> Data? { LocalFile.read(file) }
}
