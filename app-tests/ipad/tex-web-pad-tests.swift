#if os(iOS)
import FolioDomain
import FolioStorage
import Foundation
import Testing
@testable import Folio

/// The iPad's TeX build (#41) in the app's own engine: a document from Folio's template builds with its Korean, and a
/// broken one lists every error, as Tectonic does on the Mac. The first build fetches kotex's packages from TeX Live.
@MainActor @Suite(.serialized)
struct TexWebPadTests {
    static func write(_ text: String, name: String = "hw.tex", beside: [String: Data] = [:]) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "tex-web-pad-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appending(path: "figures"), withIntermediateDirectories: true)
        for (path, data) in beside { try data.write(to: folder.appending(path: path)) }
        let url = folder.appending(path: name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func theEngineShipsWithTheApp() {
        #expect(WebTex.available)
        #expect(WebTex.engine == .pdflatex)
    }

    @Test func folioTemplateBuildsWithKorean() async throws {
        let body = ["\\section{그래프 이론 과제}", "한글과 수식 $\\sum_{i=1}^n i = \\frac{n(n+1)}{2}$을 함께 쓴다.", "", "\\textbf{굵게}와 \\emph{기울임}."]
        let source = try Self.write(TexDocument.wrap(body), name: "과제 3.tex")
        let build = try await WebTex.shared.compile(source)
        #expect(build.issues.filter { $0.severity == .error } == [], "\(build.trace.joined(separator: "\n"))")
        let pdf = try #require(build.pdf)
        #expect(pdf.deletingLastPathComponent().standardizedFileURL.path == TexOutput.folder(for: source).standardizedFileURL.path)
        let data = try Data(contentsOf: pdf)
        #expect(data.prefix(5) == Data("%PDF-".utf8))
        #expect(data.count > 20_000)
        // The second build reads its packages from the caches the first one filled.
        let again = try await WebTex.shared.compile(source)
        #expect(again.issues.filter { $0.severity == .error } == [], "\(again.trace.joined(separator: "\n"))")
        #expect(again.pdf != nil)
    }

    @Test func listsEveryError() async throws {
        let text = TexDocument.wrap(["First \\undefinedone here.", "", "Second $x^2$ and \\alsoundefined.", "", "$\\frac{1}{2$"])
        let build = try await WebTex.shared.compile(try Self.write(text))
        #expect(build.pdf == nil)
        let located = build.issues.filter { $0.severity == .error && $0.file == "hw.tex" }.compactMap(\.line)
        #expect(located.starts(with: [6, 8]), "\(build.issues)")
        #expect(TexWebNotice.notices(engine: WebTex.engine, issues: build.issues) == [.otherEngine(.pdflatex)])
    }

    @Test func readsTheFilesBesideIt() async throws {
        let text = "\\documentclass{article}\n\\input{part}\n\\begin{document}\n\\partbody\n\\end{document}\n"
        let source = try Self.write(text, beside: ["part.tex": Data("\\newcommand{\\partbody}{From the other file.}\n".utf8)])
        let build = try await WebTex.shared.compile(source)
        #expect(build.issues.filter { $0.severity == .error } == [])
        #expect(build.pdf != nil)
    }

    @Test func fontspecSaysWhy() async throws {
        let text = "\\documentclass{article}\n\\usepackage{fontspec}\n\\begin{document}\nx\n\\end{document}\n"
        let build = try await WebTex.shared.compile(try Self.write(text))
        #expect(build.pdf == nil)
        #expect(TexWebNotice.notices(engine: WebTex.engine, issues: build.issues).contains(.needsXeTeX), "\(build.issues)")
    }
}
#endif
