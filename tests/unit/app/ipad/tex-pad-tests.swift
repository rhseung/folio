#if os(iOS)
import FolioDomain
import FolioStorage
import Foundation
import Testing
@testable import Folio

// 첫 빌드는 패키지를 받고 LaTeX 서식을 만들므로 몇 분이 걸린다.
@MainActor @Suite(.serialized)
struct TexPadTests {
    static func write(_ text: String, name: String = "hw.tex", beside: [String: Data] = [:]) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "tex-pad-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (path, data) in beside { try data.write(to: folder.appending(path: path)) }
        let url = folder.appending(path: name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func build(_ source: URL) async throws -> TexEngine.Build {
        try await Task.detached {
            try TexEngine.shared.compile(source, into: TexEngine.outputFolder(for: source), at: .now, calendar: .current)
        }.value
    }

    @Test func folioTemplateBuildsWithKorean() async throws {
        let body = ["\\section{그래프 이론 과제}", "한글과 수식 $\\sum_{i=1}^n i = \\frac{n(n+1)}{2}$을 함께 쓴다.", "", "\\textbf{굵게}와 \\emph{기울임}."]
        let source = try Self.write(TexDocument.wrap(body), name: "과제 3.tex")
        let build = try await Self.build(source)
        #expect(build.errors == [], "\(build.issues)")
        let pdf = try #require(build.pdf)
        #expect(pdf.deletingLastPathComponent().standardizedFileURL.path == TexOutput.folder(for: source).standardizedFileURL.path)
        let data = try Data(contentsOf: pdf)
        #expect(data.prefix(5) == Data("%PDF-".utf8))
        #expect(data.count > 20_000)
        #expect(FileManager.default.fileExists(atPath: TexEngine.synctex(for: source).path))
        let again = try await Self.build(source)
        #expect(again.errors == [], "\(again.issues)")
        #expect(try again.pdf.map { try Data(contentsOf: $0) } == data)
    }

    @Test func listsEveryError() async throws {
        let text = TexDocument.wrap(["First \\undefinedone here.", "", "Second $x^2$ and \\alsoundefined.", "", "$\\frac{1}{2$"])
        let build = try await Self.build(try Self.write(text))
        #expect(build.pdf == nil)
        let located = build.errors.filter { $0.file?.hasSuffix("hw.tex") == true }.compactMap(\.line)
        #expect(located.starts(with: [6, 8]), "\(build.issues)")
    }

    @Test func readsTheFilesBesideIt() async throws {
        let text = "\\documentclass{article}\n\\input{part}\n\\begin{document}\n\\partbody\n\\end{document}\n"
        let source = try Self.write(text, beside: ["part.tex": Data("\\newcommand{\\partbody}{From the other file.}\n".utf8)])
        let build = try await Self.build(source)
        #expect(build.errors == [], "\(build.issues)")
        #expect(build.pdf != nil)
    }

    @Test func fontspecFindsTheIPadsFonts() async throws {
        let text =
            "\\documentclass{article}\n\\usepackage{fontspec}\n\\setmainfont{Apple SD Gothic Neo}\n\\begin{document}\n한글 fontspec\n\\end{document}\n"
        let build = try await Self.build(try Self.write(text))
        #expect(build.errors == [], "\(build.issues)")
        #expect(build.pdf != nil)
    }
}
#endif
