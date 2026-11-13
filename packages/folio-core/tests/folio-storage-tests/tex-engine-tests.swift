import FolioStorage
import Foundation
import Testing

struct TexEngineTests {
    /// An xdvipdfmx abort left its PDF output handle in a global, and the next build in the process closed that dead
    /// handle: a panic Rust can't unwind out of C, so the app aborted. A form XObject left open at the end of a page is
    /// one such abort.
    @Test func aBuildAfterXdvipdfmxAbortsStillBuilds() throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let broken = folder.appending(path: "broken.tex")
        try "\\documentclass{article}\n\\begin{document}\nA\\special{pdf:bxobj @folio width 10pt height 10pt}\n\\end{document}\n"
            .write(to: broken, atomically: true, encoding: .utf8)
        let good = folder.appending(path: "good.tex")
        try "\\documentclass{article}\n\\begin{document}\nB\n\\end{document}\n".write(to: good, atomically: true, encoding: .utf8)

        let first = try TexEngine.shared.compile(broken, into: folder.appending(path: "out"), at: .now, calendar: .current)
        #expect(first.pdf == nil)
        #expect(!first.errors.isEmpty)
        let second = try TexEngine.shared.compile(good, into: folder.appending(path: "out"), at: .now, calendar: .current)
        #expect(second.errors.isEmpty)
        let pdf = try Data(contentsOf: try #require(second.pdf))
        #expect(pdf.starts(with: Data("%PDF".utf8)))
    }
}
