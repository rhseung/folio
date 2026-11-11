import FolioDomain
import Foundation
import Testing

struct TexWebLogTests {
    /// The log the web engine wrote for a file with `\undefinedone` on line 4, `\alsoundefined` on line 6 and an
    /// unclosed `\frac` on line 8, run without `--halt-on-error`: every error, then TeX's own end.
    static let three = """
        This is pdfTeX, Version 3.141592653-2.6-1.40.28 (TeX Live 2026_busytexwasm)
        (/hw3.tex
        LaTeX2e <2026-06-01>
        (/texlive/texmf-dist/tex/latex/base/article.cls
        Document Class: article 2025/01/22 v1.4n Standard LaTeX document class
        )
        /hw3.tex:4: Undefined control sequence.
        l.4 First \\undefinedone
                                 here.
        /hw3.tex:6: Undefined control sequence.
        l.6 Second $x^2$ and \\alsoundefined
        ! File ended while scanning use of \\frac .
        <inserted text>
        /hw3.tex:12: Emergency stop.
        /hw3.tex:12:  ==> Fatal error occurred, no output PDF file produced!
        """

    @Test func readsEveryErrorAndDropsTeXsOwnEnd() {
        #expect(TexLog.issues(texLog: Self.three) == [
            TexIssue(.error, file: "hw3.tex", line: 4, message: "Undefined control sequence."),
            TexIssue(.error, file: "hw3.tex", line: 6, message: "Undefined control sequence."),
            TexIssue(.error, message: "File ended while scanning use of \\frac ."),
        ])
    }

    @Test func theEndAloneStillFailsTheBuild() {
        let log = "/hw3.tex:3: Emergency stop.\n/hw3.tex:3:  ==> Fatal error occurred, no output PDF file produced!\n"
        #expect(TexLog.issues(texLog: log) == [TexIssue(.error, file: "hw3.tex", line: 3, message: "Emergency stop.")])
    }

    @Test func aPackageFileKeepsItsPathAndAFolderKeepsItsName() {
        let log = """
            /texlive/texmf-dist/tex/latex/fontspec/fontspec.sty:101: Fatal Package fontspec Error: The fontspec package requires either XeTeX or LuaTeX.
            /sections/HW 1.tex:9: Missing $ inserted.
            /hw3.tex:2: LaTeX Error: File `nonexistentpkgxyz.sty' not found.
            /hw3.tex:2: LaTeX Error: File `nonexistentpkgxyz.sty' not found.
            """
        #expect(TexLog.issues(texLog: log) == [
            TexIssue(.error, file: "/texlive/texmf-dist/tex/latex/fontspec/fontspec.sty", line: 101,
                     message: "Fatal Package fontspec Error: The fontspec package requires either XeTeX or LuaTeX."),
            TexIssue(.error, file: "sections/HW 1.tex", line: 9, message: "Missing $ inserted."),
            TexIssue(.error, file: "hw3.tex", line: 2, message: "LaTeX Error: File `nonexistentpkgxyz.sty' not found."),
        ])
    }

    @Test func keepsWarningsAfterErrors() {
        let log = """
            LaTeX Warning: Reference `fig:a' on page 1 undefined on input line 7.
            Overfull \\hbox (3.2pt too wide) in paragraph at lines 10--12
            Package hyperref Warning: Token not allowed in a PDF string (Unicode):
            /hw3.tex:5: Undefined control sequence.
            """
        #expect(TexLog.issues(texLog: log) == [
            TexIssue(.error, file: "hw3.tex", line: 5, message: "Undefined control sequence."),
            TexIssue(.warning, message: "LaTeX Warning: Reference `fig:a' on page 1 undefined on input line 7."),
            TexIssue(.warning, message: "Overfull \\hbox (3.2pt too wide) in paragraph at lines 10--12"),
            TexIssue(.warning, message: "Package hyperref Warning: Token not allowed in a PDF string (Unicode):"),
        ])
    }

    /// Info lines with colons and numbers are not errors.
    @Test func aCleanLogHasNoIssues() {
        let log = """
            This is pdfTeX, Version 3.141592653-2.6-1.40.28 (TeX Live 2026_busytexwasm)
            LaTeX Font Info:    Checking defaults for OML/cmm/m/it on input line 5.
            File: size10.clo 2025/01/22 v1.4n Standard LaTeX file (size option)
            Output written on hw3.pdf (1 page, 27908 bytes).
            Lecture at 12:30: room 101
            """
        #expect(TexLog.issues(texLog: log).isEmpty)
    }
}

struct TexProjectTests {
    static func file(_ path: String, _ size: Int = 1_000) -> TexProject.File { TexProject.File(path: path, size: size) }

    @Test func sendsWhatTeXReadsBesideTheDocument() {
        let files = [
            Self.file("hw3.tex"), Self.file("hw3.pdf"), Self.file("refs.bib"), Self.file("figures/graph.png"),
            Self.file("macros.sty"), Self.file("notes.md"), Self.file("main.py"), Self.file("handout.pdf"),
        ]
        #expect(TexProject.inputs(of: "hw3.tex", among: files) == ["figures/graph.png", "handout.pdf", "macros.sty", "refs.bib"])
    }

    @Test func leavesOutEveryBuiltPDFAndHiddenAndDeepFiles() {
        let files = [
            Self.file("hw3.tex"), Self.file("HW3.PDF"), Self.file("other.tex"), Self.file("other.pdf"),
            Self.file(".git/config.tex"), Self.file("a/b/c/d.png"), Self.file("a/b/c.png"),
        ]
        #expect(TexProject.inputs(of: "hw3.tex", among: files) == ["a/b/c.png", "other.tex"])
    }

    @Test func keepsWithinTheBudgetSmallestFirst() {
        let big = TexProject.budget - 10
        let files = [Self.file("hw3.tex"), Self.file("scan.pdf", big), Self.file("a.sty", 6), Self.file("b.png", 6)]
        #expect(TexProject.inputs(of: "hw3.tex", among: files) == ["a.sty", "b.png"])
    }
}

struct TexWebNoticeTests {
    static let failed = [TexIssue(.error, file: "hw3.tex", line: 4, message: "Undefined control sequence.")]

    @Test func aCleanBuildNeedsNoNotice() {
        #expect(TexWebNotice.notices(engine: .pdflatex, issues: []).isEmpty)
        #expect(TexWebNotice.notices(engine: .pdflatex, issues: [TexIssue(.warning, message: "LaTeX Warning: x")]).isEmpty)
    }

    @Test func errorsNameTheOtherEngine() {
        #expect(TexWebNotice.notices(engine: .pdflatex, issues: Self.failed) == [.otherEngine(.pdflatex)])
    }

    @Test func fontspecSaysItNeedsXeTeX() {
        let issues = [TexIssue(.error, file: "/texlive/texmf-dist/tex/latex/fontspec/fontspec.sty", line: 101,
                               message: "Fatal Package fontspec Error: The fontspec package requires either XeTeX or LuaTeX.")]
        #expect(TexWebNotice.notices(engine: .pdflatex, issues: issues) == [.otherEngine(.pdflatex), .needsXeTeX])
    }

    /// Once the iPad runs the Mac's TeX there is nothing to explain.
    @Test func xelatexNeedsNone() {
        #expect(TexWebNotice.notices(engine: .xelatex, issues: Self.failed).isEmpty)
    }
}
