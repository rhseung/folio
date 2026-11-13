import Foundation
import Testing

@testable import FolioStorage

struct TexEngineTests {
    // xdvipdfmx는 상태를 전역 변수에 두는데, 중단되면 그 상태가 반쯤 만들어진 채로 남았다. 받은 패키지만 쓸 때 아직 받지 않은 글꼴(이때 빌드는 온라인으로 간다)이나, 쪽 끝에서 열린 채 남은
    // form XObject가 그런 경우다. 같은 프로세스의 다음 빌드가 이미 무효가 된 PDF handle을 닫으면서 Rust가 C 밖으로 unwind할 수 없는 panic이 나서 앱이 중단되었고, 그
    // 문제를 넘긴 뒤에는 남은 캐시와 쪽 상태 때문에 실패했다. 중단 뒤의 빌드는 어느 엔진이든 중단이 없었던 것처럼 나와야 한다.
    @Test func aBuildAfterAnAbortIsUnchanged() throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let broken = folder.appending(path: "broken.tex")
        try """
        \\documentclass{article}
        \\usepackage{xcolor}
        \\usepackage{hyperref}
        \\begin{document}
        \\section{A}
        \\href{https://example.com}{\\textcolor{red}{$a$\\special{pdf:bxobj @folio width 10pt height 10pt}}}
        \\end{document}

        """.write(to: broken, atomically: true, encoding: .utf8)
        // XeTeX은 xdvipdfmx가 돌기 전에 파일 끝에서 멈춘다.
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

    // xdvipdfmx는 글꼴의 metric을 찾은 TeX 단계 뒤에, 찾지 못한 글꼴을 자기 말로 알린다.
    @Test func aFontOnlyThePDFNeedsSendsTheBuildOnline() {
        #expect(TexEngine.missesAFile("warning: Could not locate a virtual/physical font for TFM \"cmmi10\".\n"))
        #expect(!TexEngine.missesAFile("error: hw.tex:3: Undefined control sequence\n"))
    }
}
