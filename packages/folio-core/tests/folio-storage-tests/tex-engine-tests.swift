@testable import FolioStorage
import Foundation
import Testing

struct TexEngineTests {
    /// xdvipdfmx keeps its state in globals, and an abort left them half built: a font not fetched yet when only fetched
    /// packages are used (then the build goes online), or a form XObject left open at the end of a page. The next build in
    /// the process closed the dead PDF handle, a panic Rust can't unwind out of C, so the app aborted; past that it
    /// tripped on the leftover caches and page state. A build after an abort, of either engine, must come out as if the
    /// abort never happened.
    @Test func aBuildAfterAnAbortIsUnchanged() throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let broken = folder.appending(path: "broken.tex")
        // The abort comes mid-page, inside a link and a color, so their stacks are left full.
        try """
            \\documentclass{article}
            \\usepackage{xcolor}
            \\usepackage{hyperref}
            \\begin{document}
            \\section{A}
            \\href{https://example.com}{\\textcolor{red}{$a$\\special{pdf:bxobj @folio width 10pt height 10pt}}}
            \\end{document}

            """.write(to: broken, atomically: true, encoding: .utf8)
        // XeTeX gives up at the end of the file, before xdvipdfmx runs.
        let unfinished = folder.appending(path: "unfinished.tex")
        try "\\documentclass{article}\n\\begin{document}\n\\textcolor{red}{A\n".write(to: unfinished, atomically: true, encoding: .utf8)
        let good = folder.appending(path: "good.tex")
        try """
            \\documentclass{article}
            \\usepackage{xcolor}
            \\usepackage{hyperref}
            \\begin{document}
            \\section{B}
            \\href{https://example.com}{\\textcolor{blue}{$x^2$}}
            \\newpage
            \\section{C}
            \\textcolor{red}{C} \\ref{c}\\label{c}
            \\end{document}

            """.write(to: good, atomically: true, encoding: .utf8)
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        func build(_ source: URL) throws -> TexEngine.Build {
            try TexEngine.shared.compile(source, into: folder.appending(path: "out"), at: day, calendar: .current)
        }

        let first = try build(good)
        let before = try Data(contentsOf: try #require(first.pdf, "\(first.issues)"))
        for source in [broken, unfinished, broken] {
            let failed = try build(source)
            #expect(failed.pdf == nil)
            #expect(!failed.errors.isEmpty)
            let after = try build(good)
            #expect(after.errors.isEmpty)
            #expect(try Data(contentsOf: try #require(after.pdf, "\(after.issues)")) == before)
        }
    }

    /// xdvipdfmx names a font it couldn't find in its own words, past the TeX pass that found the font's metrics.
    @Test func aFontOnlyThePDFNeedsSendsTheBuildOnline() {
        #expect(TexEngine.missesAFile("warning: Could not locate a virtual/physical font for TFM \"cmmi10\".\n"))
        #expect(!TexEngine.missesAFile("error: hw.tex:3: Undefined control sequence\n"))
    }
}
