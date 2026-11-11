#if os(iOS)
import FolioDomain
import FolioStorage
import Foundation
import UniformTypeIdentifiers
import WebKit

/// The iPad's TeX build (#41). iPadOS doesn't let an app start Tectonic, so the iPad runs TeX Live compiled to
/// WebAssembly (Siglum's BusyTeX) in a hidden web view. The engine ships in the app (`mise run tex-engine`), as code
/// can't be downloaded (App Store 2.5.2); TeX Live packages it lacks are data, fetched once from a CTAN mirror of TeX Live and
/// kept in Caches.
@MainActor final class WebTex: NSObject, WKNavigationDelegate {
    static let shared = WebTex()

    struct Build {
        var pdf: URL?
        var issues: [TexIssue]
        /// The engine's own log (fetches, retries), for a test to show why a build failed.
        var trace: [String] = []
    }

    /// From `tex-engine.json`, the file the fetch step reads too.
    struct Pin: Decodable, Sendable {
        struct TeXLive: Decodable, Sendable { var archive: URL }
        var engine: TexWebEngine
        var texlive: TeXLive
    }

    nonisolated static let pin: Pin? = Bundle.main.url(forResource: "tex-engine", withExtension: "json")
        .flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(Pin.self, from: $0) }
    /// A build made without `mise run tex-engine` has the folder, empty.
    nonisolated static let folder: URL? = Bundle.main.url(forResource: "TexEngine", withExtension: nil)
        .flatMap { FileManager.default.fileExists(atPath: $0.appending(path: "wasm/busytex.wasm").path) ? $0 : nil }
    nonisolated static var available: Bool { pin != nil && folder != nil }
    nonisolated static var engine: TexWebEngine { pin?.engine ?? .pdflatex }

    private var web: WKWebView?
    private var loading: WKNavigation?
    private var loaded = false
    private var onLoad: [CheckedContinuation<Bool, Never>] = []
    /// One build at a time: the engine holds one document in its file system.
    private var running: Task<Void, Never>?

    func compile(_ source: URL) async throws -> Build {
        let previous = running
        let task = Task { () throws -> Build in
            _ = await previous?.value
            return try await self.run(source)
        }
        running = Task { _ = try? await task.value }
        return try await task.value
    }

    private func run(_ source: URL) async throws -> Build {
        guard Self.available, await page() else { return Build(pdf: nil, issues: [TexIssue(.error, message: String(localized: .textFileEngineUnavailable))]) }
        let job = try await Task.detached { try Self.job(for: source) }.value
        let arguments: [String: Any] = ["engine": job.engine, "mainFile": job.mainFile, "source": job.source, "files": job.files]
        let answer = try await web?.callAsyncJavaScript("return await window.folioTex.compile({engine, mainFile, source, files})",
                                                        arguments: arguments, contentWorld: .page)
        guard let answer = answer as? [String: Any] else { throw URLError(.cannotParseResponse) }
        let log = answer["log"] as? String ?? ""
        var issues = TexLog.issues(texLog: log)
        let pdf = (answer["pdf"] as? String).flatMap { Data(base64Encoded: $0) }
        let trace = answer["trace"] as? [String] ?? []
        if pdf == nil, !issues.contains(where: { $0.severity == .error }) {
            let reason = answer["error"] as? String ?? log.split(whereSeparator: \.isNewline).last.map(String.init) ?? "TeX"
            issues.insert(TexIssue(.error, message: reason), at: 0)
        }
        // As on the Mac: past an error the PDF has the broken parts left out, and placed beside the source it would
        // replace a good one.
        guard let pdf, !issues.contains(where: { $0.severity == .error }) else { return Build(pdf: nil, issues: issues, trace: trace) }
        let folder = TexOutput.folder(for: source)
        // folio:not-an-action the build output folder is in temp, outside the GIST folder; `material build` places it
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: source.deletingPathExtension().lastPathComponent + ".pdf")
        // folio:not-an-action the build output folder is in temp, outside the GIST folder; `material build` places it
        try pdf.write(to: url, options: .atomic)
        return Build(pdf: url, issues: issues, trace: trace)
    }

    /// The engine sees only what it is sent: the document, and the files beside it TeX may read (`TexProject`).
    private struct Job: Sendable {
        var engine: String
        var mainFile: String
        var source: String
        /// Relative to the document's folder, in base64.
        var files: [String: String]
    }

    nonisolated private static func job(for source: URL) throws -> Job {
        guard let data = LocalFile.read(source) else { throw CocoaError(.fileReadNoSuchFile) }
        let folder = source.deletingLastPathComponent().standardizedFileURL
        var found: [TexProject.File] = []
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        if let walk = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let url as URL in walk {
                let relative = String(url.standardizedFileURL.path.dropFirst(folder.path.count + 1))
                if relative.split(separator: "/").count >= TexProject.depth { walk.skipDescendants() }
                guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
                found.append(TexProject.File(path: relative, size: values.fileSize ?? 0))
            }
        }
        var files: [String: String] = [:]
        for path in TexProject.inputs(of: source.lastPathComponent, among: found) {
            if let data = LocalFile.read(folder.appending(path: path)) { files[path] = data.base64EncodedString() }
        }
        return Job(engine: engine.rawValue, mainFile: source.lastPathComponent, source: String(decoding: data, as: UTF8.self), files: files)
    }

    /// Made on the first build: an iPad that never builds never starts the engine.
    private func page() async -> Bool {
        if loaded { return true }
        if web == nil {
            let config = WKWebViewConfiguration()
            config.setURLSchemeHandler(WebTexFiles(), forURLScheme: WebTexFiles.scheme)
            let made = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
            made.navigationDelegate = self
            web = made
            load()
        }
        return await withCheckedContinuation { onLoad.append($0) }
    }

    private func load() {
        loading = web?.load(URLRequest(url: WebTexFiles.page))
    }

    private func finish(_ ok: Bool) {
        loaded = ok
        onLoad.forEach { $0.resume(returning: ok) }
        onLoad = []
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if navigation === loading { finish(true) }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        if navigation === loading { finish(false) }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        if navigation === loading { finish(false) }
    }

    // A build can take the web process past its memory; the next one starts a fresh page.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loaded = false
        web = nil
    }
}

/// Serves the TeX page, its scripts and the engine from the app, and answers the engine's requests for TeX Live
/// packages (`/p/api/texlive/<name>`, Siglum's proxy route) from Caches or a CTAN mirror.
@MainActor final class WebTexFiles: NSObject, WKURLSchemeHandler {
    static let scheme = "folio-tex"
    static let page = URL(string: "\(scheme)://engine/index.html")!
    nonisolated private static let html = "<!doctype html><meta charset=utf-8><script src=\"tex-engine.js\"></script>"

    private var running = Set<ObjectIdentifier>()

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else { return task.didFailWithError(URLError(.badURL)) }
        let id = ObjectIdentifier(task as AnyObject)
        running.insert(id)
        Task {
            let (status, data, type) = await Self.answer(url.path(percentEncoded: false))
            guard running.remove(id) != nil else { return }
            let headers = ["Content-Type": type, "Content-Length": String(data.count)]
            task.didReceive(HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!)
            task.didReceive(data)
            task.didFinish()
        }
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) { running.remove(ObjectIdentifier(task as AnyObject)) }

    nonisolated private static func answer(_ path: String) async -> (Int, Data, String) {
        let missing = (404, Data(), "text/plain")
        if path == "/index.html" { return (200, Data(html.utf8), "text/html") }
        if path == "/tex-engine.js" || path == "/tex-worker.js",
           let url = Bundle.main.url(forResource: String(path.dropFirst()), withExtension: nil), let data = try? Data(contentsOf: url) {
            return (200, data, "text/javascript")
        }
        // Siglum's file table lacks most fonts, so each font kotex misses would look like a package of its own and be
        // fetched, unpacked and written by itself; asked here, they all come to one package and one fetch.
        if path.hasPrefix("/p/api/package-of/") {
            let name = String(path.dropFirst("/p/api/package-of/".count))
            guard let package = await TexPackages.shared.package(of: name) else { return missing }
            return (200, Data(package.utf8), "text/plain")
        }
        if path.hasPrefix("/p/api/texlive/") {
            let name = String(path.dropFirst("/p/api/texlive/".count))
            guard let data = await TexPackages.shared.archive(for: name) else { return missing }
            return (200, data, "application/x-xz")
        }
        // The package finder reads its file tables beside the proxy (`/p/bundles`), the engine beside the page (`/rt`).
        let inside: String? = path.hasPrefix("/rt/") ? String(path.dropFirst(4)) : path.hasPrefix("/p/bundles/") ? "bundles/" + path.dropFirst(11) : nil
        guard let inside, let root = WebTex.folder?.standardizedFileURL else { return missing }
        let file = root.appending(path: inside).standardizedFileURL
        guard file.path.hasPrefix(root.path + "/"), let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { return missing }
        let type = switch file.pathExtension {
        case "wasm": "application/wasm"
        case "js": "text/javascript"
        case "json": "application/json"
        // Not `application/gzip`: the engine unpacks the bundles itself, and an encoding would have the page do it first.
        default: "application/octet-stream"
        }
        return (200, data, type)
    }
}

/// TeX Live packages the engine asked for, by the file TeX missed or the package's name. Kept in Caches by package:
/// kotex's Korean fonts are a few hundred files of one package (uhc), asked for one by one.
actor TexPackages {
    static let shared = TexPackages()
    private let folder = URL.cachesDirectory.appending(path: "Folio/TexPackages")
    /// File name to package, from the snapshot's package database (`files.tsv`, made by the fetch step).
    private var owners: [String: String]?
    private var packages: Set<String> = []

    func package(of name: String) -> String? {
        Self.valid(name) ? candidates(for: name).first : nil
    }

    func archive(for name: String) async -> Data? {
        guard Self.valid(name), let archive = WebTex.pin?.texlive.archive else { return nil }
        for package in candidates(for: name) {
            let cached = folder.appending(path: "\(package).tar.xz")
            if let data = try? Data(contentsOf: cached), Self.isXZ(data) { return data }
            // A mirror or a bot check in front of one can answer 200 with a web page; kept, it would stand in for the
            // package on every later build.
            guard let (data, response) = try? await URLSession.shared.data(from: archive.appending(path: "\(package).tar.xz")),
                  (response as? HTTPURLResponse)?.statusCode == 200, Self.isXZ(data) else { continue }
            // folio:not-an-action TeX Live packages are cached in this device's caches, outside the GIST folder
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // folio:not-an-action TeX Live packages are cached in this device's caches, outside the GIST folder
            try? data.write(to: cached, options: .atomic)
            return data
        }
        return nil
    }

    private static func valid(_ name: String) -> Bool {
        name.allSatisfy { $0.isLetter || $0.isNumber || "-_.".contains($0) } && !name.hasPrefix(".")
    }

    private static func isXZ(_ data: Data) -> Bool { data.starts(with: [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]) }

    /// The engine asks by package name, or by the name of a file it missed without its extension (`kotex`, `uwmjac`).
    private func candidates(for name: String) -> [String] {
        let owners = loadOwners()
        var found: [String] = packages.contains(name) ? [name] : []
        for ext in ["sty", "cls", "tex", "tfm", "fd", "def", "cfg", "clo", "ldf", "vf", "pfb", "enc", "map", "bst"] {
            if let package = owners["\(name).\(ext)"], !found.contains(package) { found.append(package) }
        }
        if let package = owners[name], !found.contains(package) { found.append(package) }
        return found
    }

    private func loadOwners() -> [String: String] {
        if let owners { return owners }
        var table: [String: String] = [:]
        if let url = WebTex.folder?.appending(path: "files.tsv"), let text = try? String(contentsOf: url, encoding: .utf8) {
            for line in text.split(separator: "\n") {
                guard let tab = line.firstIndex(of: "\t") else { continue }
                let package = String(line[line.index(after: tab)...])
                table[String(line[..<tab])] = package
                packages.insert(package)
            }
        }
        owners = table
        return table
    }
}
#endif
