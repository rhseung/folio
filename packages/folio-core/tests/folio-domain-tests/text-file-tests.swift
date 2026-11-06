import FolioDomain
import Foundation
import Testing

struct MaterialFormatTests {
    @Test func judgesByExtension() {
        #expect(MaterialFormat(path: "Assignments/HW01/hw.tex") == .tex)
        #expect(MaterialFormat(path: "Lectures/05_Matchings.PDF") == .pdf)
        #expect(MaterialFormat(path: "Notes/2주차-1.md") == .markdown)
        #expect(MaterialFormat(path: "Assignments/Lab03/main.cpp") == .code(language: "cpp"))
        #expect(MaterialFormat(path: "Assignments/HW01/refs.bib") == .text)
        #expect(MaterialFormat(path: "Assignments/HW01/macros.sty") == .code(language: "latex"))
        #expect(MaterialFormat(path: "Recordings/2주차-1.m4a") == .other)
        #expect(MaterialFormat(path: "Makefile") == .other)
    }

    @Test func onlyTextIsEditable() {
        #expect(MaterialFormat.tex.isText)
        #expect(MaterialFormat.code(language: "python").isText)
        #expect(!MaterialFormat.pdf.isText)
        #expect(!MaterialFormat.other.isText)
        #expect(!MaterialFormat.markdown.isText)
    }

    @Test func aTexBuildsToTheSameNamedPDF() {
        #expect(MaterialFormat.builtPDF(of: "Exams/Midterm/Problems.TEX") == "Exams/Midterm/Problems.pdf")
        #expect(MaterialFormat.builtPDF(of: "Exams/Midterm/Problems.pdf") == nil)
    }

    @Test func texHighlightsAsLatex() {
        #expect(MaterialFormat.tex.highlightLanguage == "latex")
        #expect(MaterialFormat.text.highlightLanguage == nil)
    }
}

struct TexLogTests {
    // Tectonic's console output for a file with `\foo` on line 5, as it printed it.
    static let undefined = """
        note: "version 2" Tectonic command-line interface activated
        note: Running TeX ...
        error: bad.tex:5: Undefined control sequence
        note: Writing `out/bad.log` (3.5224609375 KiB)
        error: something bad happened inside XeTeX; its output follows:
        ! Undefined control sequence.
        l.5 \\foo
        error: the XeTeX engine had an unrecoverable error
        caused by: halted on potentially-recoverable error as specified
        """

    @Test func locatedErrorHidesTheGenericOnesAfterIt() {
        #expect(TexLog.issues(Self.undefined) == [TexIssue(.error, file: "bad.tex", line: 5, message: "Undefined control sequence")])
    }

    @Test func keepsWarningsAndNamesWithSpacesAndColons() {
        let output = """
            warning: HW 1.tex:12: Overfull \\hbox (3.2pt too wide) in paragraph
            error: sections/a:b.tex:40: Missing $ inserted
            """
        #expect(TexLog.issues(output) == [
            TexIssue(.warning, file: "HW 1.tex", line: 12, message: "Overfull \\hbox (3.2pt too wide) in paragraph"),
            TexIssue(.error, file: "sections/a:b.tex", line: 40, message: "Missing $ inserted"),
        ])
    }

    @Test func withoutALocationTheFirstErrorStands() {
        let output = """
            error: failed to open input file "missing.tex"
            error: the XeTeX engine had an unrecoverable error
            """
        #expect(TexLog.issues(output) == [TexIssue(.error, message: "failed to open input file \"missing.tex\"")])
    }

    /// Tectonic with `-Z continue-on-errors`, as it printed it for a file with three mistakes and a missing package:
    /// every error, then all of them again on the `.aux` rerun.
    @Test func collectsEveryErrorOnce() {
        let output = """
            note: Running TeX ...
            error: hw.tex:2: ! LaTeX Error: File `nonexistentpkgxyz.sty' not found.
            error: hw.tex:3: Undefined control sequence
            error: hw.tex:3: Undefined control sequence
            error: hw.tex:2: LaTeX Error: The package . failed to load.

            See the LaTeX manual or LaTeX Companion for explanation.
            error: hw.tex:5: Missing $ inserted
            note: Rerunning TeX because "hw.aux" changed ...
            error: hw.tex:2: ! LaTeX Error: File `nonexistentpkgxyz.sty' not found.
            error: hw.tex:3: Undefined control sequence
            error: hw.tex:5: Missing $ inserted
            warning: errors were issued by the TeX engine, but were ignored; use --print and/or --keep-logs for details.
            note: Writing `out/hw.pdf` (6.9 KiB)
            """
        #expect(TexLog.issues(output) == [
            TexIssue(.error, file: "hw.tex", line: 2, message: "LaTeX Error: File `nonexistentpkgxyz.sty' not found."),
            TexIssue(.error, file: "hw.tex", line: 3, message: "Undefined control sequence"),
            TexIssue(.error, file: "hw.tex", line: 2, message: "LaTeX Error: The package . failed to load."),
            TexIssue(.error, file: "hw.tex", line: 5, message: "Missing $ inserted"),
        ])
    }

    /// Errors ignored without an `error:` line of their own still fail the build.
    @Test func ignoredErrorsAloneAreAnError() {
        let output = """
            note: Running TeX ...
            warning: errors were issued by the TeX engine, but were ignored; use --print and/or --keep-logs for details.
            note: Writing `out/hw.pdf` (6.9 KiB)
            """
        #expect(TexLog.issues(output) == [
            TexIssue(.error, message: "errors were issued by the TeX engine, but were ignored; use --print and/or --keep-logs for details."),
        ])
    }

    @Test func aCleanBuildHasNoIssues() {
        #expect(TexLog.issues("note: Running TeX ...\nnote: Writing `hw.pdf` (21.5 KiB)\n").isEmpty)
    }

    @Test func describesWithItsLocation() {
        #expect(TexIssue(.error, file: "hw.tex", line: 5, message: "Undefined").description == "hw.tex:5: Undefined")
        #expect(TexIssue(.error, message: "Boom").description == "Boom")
    }
}
