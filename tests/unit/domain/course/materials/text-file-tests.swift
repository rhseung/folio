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
        #expect(MaterialFormat(path: "Recordings/2주차-1.m4a") == .audio)
        #expect(MaterialFormat(path: "Notes/assets/board.JPG") == .image)
        #expect(MaterialFormat(path: "Study/widget.html") == .html)
        #expect(MaterialFormat(path: "Lectures/05_Matchings.pptx") == .other)
        #expect(MaterialFormat(path: "Makefile") == .other)
    }

    /// The renderer table of #179: the app draws what it can, Quick Look the rest.
    @Test func picksARendererPerFormat() {
        #expect(MaterialFormat(path: "a.pdf").renderer == .pdf)
        #expect(MaterialFormat(path: "a.md").renderer == .markdown)
        #expect(MaterialFormat(path: "a.tex").renderer == .source)
        #expect(MaterialFormat(path: "a.py").renderer == .source)
        #expect(MaterialFormat(path: "a.csv").renderer == .source)
        #expect(MaterialFormat(path: "a.png").renderer == .image)
        #expect(MaterialFormat(path: "a.m4a").renderer == .audio)
        #expect(MaterialFormat(path: "a.html").renderer == .quickLook)
        #expect(MaterialFormat(path: "a.docx").renderer == .quickLook)
        #expect(MaterialFormat(path: "a.hwp").renderer == .quickLook)
    }

    @Test func aFolderHasNoFormat() {
        let folder = Material(device: UUID(), at: .now, path: "Assignments/Lab03/robot.pdf", isFolder: true, status: .classified)
        let pdf = Material(device: UUID(), at: .now, path: "Lectures/01.PDF", status: .classified)
        #expect(folder.format == nil && !folder.isPDF && !folder.isText)
        #expect(pdf.format == .pdf && pdf.isPDF)
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

struct TexBuildTimeTests {
    static func calendar(_ zone: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        return calendar
    }

    static func at(day: Int, _ hour: Int, _ minute: Int, _ calendar: Calendar) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute)))
    }

    // 2026-11-05 00:00 in Seoul (UTC+9), worked out by hand as 2026-11-04 15:00 UTC.
    static let nov5Seoul = 1_793_804_400

    @Test func aBuildIsStampedWithMidnightOfItsDay() throws {
        let seoul = try Self.calendar("Asia/Seoul")
        #expect(TexBuildTime.sourceDateEpoch(at: try Self.at(day: 5, 0, 0, seoul), calendar: seoul) == Self.nov5Seoul)
        #expect(TexBuildTime.sourceDateEpoch(at: try Self.at(day: 5, 13, 30, seoul), calendar: seoul) == Self.nov5Seoul)
        #expect(TexBuildTime.sourceDateEpoch(at: try Self.at(day: 5, 23, 59, seoul), calendar: seoul) == Self.nov5Seoul)
        #expect(TexBuildTime.sourceDateEpoch(at: try Self.at(day: 6, 0, 0, seoul), calendar: seoul) == Self.nov5Seoul + 86_400)
    }

    /// `\today` prints a calendar date, so 01:00 is already the new day though the study day (04:00 boundary) isn't.
    @Test func theDayTurnsAtMidnightNotAtTheStudyDayBoundary() throws {
        let seoul = try Self.calendar("Asia/Seoul")
        #expect(TexBuildTime.sourceDateEpoch(at: try Self.at(day: 6, 1, 0, seoul), calendar: seoul) == Self.nov5Seoul + 86_400)
    }

    @Test func theDayIsTheCalendarTimeZones() throws {
        let seoul = try Self.calendar("Asia/Seoul")
        let utc = try Self.calendar("UTC")
        let moment = try Self.at(day: 5, 8, 0, seoul)  // 2026-11-04 23:00 UTC
        #expect(TexBuildTime.sourceDateEpoch(at: moment, calendar: seoul) == Self.nov5Seoul)
        #expect(TexBuildTime.sourceDateEpoch(at: moment, calendar: utc) == Self.nov5Seoul + 9 * 3600 - 86_400)
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
        #expect(
            TexLog.issues(output) == [
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
        #expect(
            TexLog.issues(output) == [
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
        #expect(
            TexLog.issues(output) == [
                TexIssue(
                    .error, message: "errors were issued by the TeX engine, but were ignored; use --print and/or --keep-logs for details.")
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
